import pytest
from django.contrib.gis.geos import Point
from django.db.models import ProtectedError

from apps.reportes.models import ReporteCiudadano

pytestmark = pytest.mark.django_db


def test_reporte_nuevo_queda_pendiente(reporte):
    assert reporte.estado == ReporteCiudadano.Estado.PENDIENTE
    assert reporte.validado_por is None and reporte.fecha_validacion is None


def test_administrador_valida(reporte, administrador):
    reporte.validar(administrador)
    reporte.refresh_from_db()
    assert reporte.estado == ReporteCiudadano.Estado.VALIDADO
    assert reporte.validado_por == administrador
    assert reporte.fecha_validacion is not None


def test_administrador_rechaza(reporte, administrador):
    reporte.rechazar(administrador)
    reporte.refresh_from_db()
    assert reporte.estado == ReporteCiudadano.Estado.RECHAZADO


@pytest.mark.parametrize("quien", ["ciudadano", "staff"])
def test_solo_un_administrador_puede_resolver(reporte, request, quien):
    with pytest.raises(PermissionError):
        reporte.validar(request.getfixturevalue(quien))
    reporte.refresh_from_db()
    assert reporte.estado == ReporteCiudadano.Estado.PENDIENTE


def test_no_se_resuelve_dos_veces(reporte, administrador):
    reporte.validar(administrador)
    with pytest.raises(ValueError):
        reporte.rechazar(administrador)


def test_distancia_reportada_un_grado_de_latitud_son_111_km(crear_reporte):
    r = crear_reporte(incendio=Point(-75.0, 6.0, srid=4326), usuario=Point(-75.0, 7.0, srid=4326))
    assert r.distancia_reportada() == pytest.approx(111.19, abs=0.1)


def test_distancia_cero_si_coinciden(reporte):
    assert reporte.distancia_reportada() == pytest.approx(0)


def test_no_se_puede_borrar_un_ciudadano_con_reportes(reporte, ciudadano):
    with pytest.raises(ProtectedError):
        ciudadano.delete()
