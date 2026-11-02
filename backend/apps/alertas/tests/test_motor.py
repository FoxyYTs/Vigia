from datetime import timedelta
from unittest.mock import patch

import pytest
from django.contrib.gis.geos import Point
from django.utils import timezone

from apps.alertas.models import Alerta, AlertaReporte
from apps.alertas.motor import MotorAlertas
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Usuario
from conftest import RIONEGRO

pytestmark = pytest.mark.django_db

Tipo = Alerta.TipoDisparador
motor = MotorAlertas()


def al_norte(km):
    """Punto `km` kilómetros al norte de Rionegro (1° de latitud ≈ 111,2 km)."""
    return Point(RIONEGRO.x, RIONEGRO.y + km / 111.2, srid=4326)


@pytest.fixture
def crear_foco(db):
    def _crear(ubicacion=RIONEGRO, hace=timedelta(hours=2), confianza="n"):
        return FocoIncendio.objects.create(
            fuente=FocoIncendio.Fuente.NASA_FIRMS,
            ubicacion=ubicacion,
            fecha_hora=timezone.now() - hace,
            confianza=confianza,
        )

    return _crear


@pytest.fixture
def ciudadanos(db):
    return [
        # Cuentas con más de 24 h: las nuevas no cuentan para la acumulación.
        Usuario.objects.create_user(
            f"vecino{i}", password="clave-segura-x", rol=Usuario.Rol.CIUDADANO,
            date_joined=timezone.now() - timedelta(days=2),
        )
        for i in range(4)
    ]


# --- Detección satelital ---


def test_foco_nuevo_crea_alerta_satelital(crear_foco):
    foco = crear_foco()
    alerta = motor.evaluar_foco_nuevo(foco)
    assert alerta.tipo_disparador == Tipo.DETECCION_SATELITAL and alerta.foco == foco


def test_focos_cercanos_se_agrupan_en_una_sola_alerta(crear_foco):
    motor.evaluar_foco_nuevo(crear_foco())
    assert motor.evaluar_foco_nuevo(crear_foco(al_norte(4))) is None
    assert motor.evaluar_foco_nuevo(crear_foco(al_norte(6))) is not None
    assert Alerta.objects.count() == 2


def test_agrupacion_satelital_vence_a_las_24_horas(crear_foco):
    vieja = motor.evaluar_foco_nuevo(crear_foco())
    Alerta.objects.filter(pk=vieja.pk).update(fecha_creacion=timezone.now() - timedelta(hours=25))
    assert motor.evaluar_foco_nuevo(crear_foco(al_norte(1))) is not None


def test_foco_viirs_de_confianza_baja_no_alerta(crear_foco):
    assert motor.evaluar_foco_nuevo(crear_foco(confianza="l")) is None
    assert not Alerta.objects.exists()


# --- Coincidencia geográfica ---


def test_reporte_a_9_km_de_un_foco_reciente_coincide(crear_foco, crear_reporte):
    foco = crear_foco()
    reporte = crear_reporte(incendio=al_norte(9))
    alerta = motor.evaluar_reporte_nuevo(reporte)
    assert alerta.tipo_disparador == Tipo.COINCIDENCIA_GEOGRAFICA and alerta.foco == foco
    # Se publica la ubicación del satélite, no el pin sin validar del ciudadano.
    assert alerta.ubicacion == foco.ubicacion
    assert AlertaReporte.objects.get(alerta=alerta, reporte=reporte).es_disparador is True


def test_reporte_a_11_km_no_coincide(crear_foco, crear_reporte):
    crear_foco()
    assert motor.evaluar_reporte_nuevo(crear_reporte(incendio=al_norte(11))) is None


def test_foco_de_hace_dos_dias_no_cuenta_como_activo(crear_foco, crear_reporte):
    crear_foco(hace=timedelta(days=2))
    assert motor.evaluar_reporte_nuevo(crear_reporte()) is None


def test_se_compara_contra_la_ubicacion_del_incendio_no_la_del_usuario(crear_foco, crear_reporte):
    crear_foco()
    # El ciudadano está junto al foco, pero dice que el incendio está a 50 km.
    assert motor.evaluar_reporte_nuevo(crear_reporte(incendio=al_norte(50), usuario=RIONEGRO)) is None


def test_segundo_reporte_del_mismo_foco_corrobora_la_alerta(crear_foco, crear_reporte):
    crear_foco()
    alerta = motor.evaluar_reporte_nuevo(crear_reporte())
    segundo = crear_reporte()
    assert motor.evaluar_reporte_nuevo(segundo) is None
    assert AlertaReporte.objects.get(alerta=alerta, reporte=segundo).es_disparador is False


# --- Acumulación de reportes ---


def test_tres_ciudadanos_distintos_disparan_acumulacion(crear_reporte, ciudadanos):
    r1 = crear_reporte(ciudadano=ciudadanos[0])
    r2 = crear_reporte(ciudadano=ciudadanos[1], incendio=al_norte(3))
    assert motor.evaluar_reporte_nuevo(r2) is None
    r3 = crear_reporte(ciudadano=ciudadanos[2], incendio=al_norte(2))
    alerta = motor.evaluar_reporte_nuevo(r3)
    assert alerta.tipo_disparador == Tipo.ACUMULACION_REPORTES
    assert set(alerta.reportes.all()) == {r1, r2, r3}
    assert list(AlertaReporte.objects.filter(es_disparador=True).values_list("reporte", flat=True)) == [r3.pk]


def test_tres_reportes_del_mismo_ciudadano_no_acumulan(crear_reporte):
    for _ in range(3):
        resultado = motor.evaluar_reporte_nuevo(crear_reporte())
    assert resultado is None


def test_reportes_de_hace_mas_de_una_hora_no_acumulan(crear_reporte, ciudadanos):
    viejos = [crear_reporte(ciudadano=c) for c in ciudadanos[:2]]
    ReporteCiudadano.objects.filter(pk__in=[r.pk for r in viejos]).update(
        fecha_creacion=timezone.now() - timedelta(hours=2)
    )
    assert motor.evaluar_reporte_nuevo(crear_reporte(ciudadano=ciudadanos[2])) is None


def test_reportes_rechazados_no_acumulan(crear_reporte, ciudadanos):
    for c in ciudadanos[:2]:
        crear_reporte(ciudadano=c, estado=ReporteCiudadano.Estado.RECHAZADO)
    assert motor.evaluar_reporte_nuevo(crear_reporte(ciudadano=ciudadanos[2])) is None


def test_cuarto_reporte_se_suma_a_la_acumulacion_existente(crear_reporte, ciudadanos):
    alerta = [motor.evaluar_reporte_nuevo(crear_reporte(ciudadano=c)) for c in ciudadanos[:3]][-1]
    cuarto = crear_reporte(ciudadano=ciudadanos[3])
    assert motor.evaluar_reporte_nuevo(cuarto) is None
    assert Alerta.objects.count() == 1 and cuarto in alerta.reportes.all()


# --- Validación manual ---


def test_validacion_manual_crea_alerta_con_el_reporte(reporte):
    alerta = motor.evaluar_validacion_manual(reporte)
    assert alerta.tipo_disparador == Tipo.VALIDACION_MANUAL
    assert AlertaReporte.objects.get(alerta=alerta).reporte == reporte


def test_crear_alerta_programa_el_despacho(crear_foco, django_capture_on_commit_callbacks):
    with patch("apps.alertas.motor.despachar_alerta") as tarea, django_capture_on_commit_callbacks(execute=True):
        alerta = motor.evaluar_foco_nuevo(crear_foco())
    tarea.delay.assert_called_once_with(alerta.pk)


def test_cuentas_recien_creadas_no_disparan_acumulacion(crear_reporte):
    nuevas = [
        Usuario.objects.create_user(f"nueva{i}", password="clave-segura-x", rol=Usuario.Rol.CIUDADANO)
        for i in range(3)
    ]
    resultados = [motor.evaluar_reporte_nuevo(crear_reporte(ciudadano=c)) for c in nuevas]
    assert resultados == [None, None, None]
