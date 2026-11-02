import pytest
from django.db import IntegrityError

from apps.alertas.models import Alerta, AlertaReporte

pytestmark = pytest.mark.django_db


@pytest.fixture
def alerta(foco):
    return Alerta.objects.create(
        tipo_disparador=Alerta.TipoDisparador.DETECCION_SATELITAL, foco=foco, ubicacion=foco.ubicacion
    )


def test_alerta_guarda_el_disparador_y_el_foco(alerta, foco):
    assert alerta.tipo_disparador == "deteccion_satelital"
    assert alerta.foco == foco and foco.alertas.count() == 1


def test_asociar_reporte_registra_disparador_y_fecha(alerta, reporte):
    alerta.reportes.add(reporte, through_defaults={"es_disparador": True})
    vinculo = AlertaReporte.objects.get(alerta=alerta, reporte=reporte)
    assert vinculo.es_disparador is True and vinculo.fecha_asociacion is not None


def test_es_disparador_por_defecto_es_falso(alerta, reporte):
    alerta.reportes.add(reporte)
    assert AlertaReporte.objects.get().es_disparador is False


def test_un_reporte_no_se_asocia_dos_veces_a_la_misma_alerta(alerta, reporte):
    AlertaReporte.objects.create(alerta=alerta, reporte=reporte)
    with pytest.raises(IntegrityError):
        AlertaReporte.objects.create(alerta=alerta, reporte=reporte)


def test_alerta_sin_foco_es_valida(reporte):
    a = Alerta.objects.create(
        tipo_disparador=Alerta.TipoDisparador.VALIDACION_MANUAL, ubicacion=reporte.ubicacion_incendio
    )
    assert a.foco is None
