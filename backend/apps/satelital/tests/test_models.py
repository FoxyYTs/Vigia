import pytest
from django.contrib.gis.geos import Point

pytestmark = pytest.mark.django_db


def test_reportes_cercanos_incluye_los_del_radio(foco, crear_reporte):
    cerca = crear_reporte(incendio=Point(-75.3937, 6.1552, srid=4326))  # ~2.2 km
    lejos = crear_reporte(incendio=Point(-75.0, 7.0, srid=4326))  # ~100 km
    resultado = list(foco.reportes_cercanos(radio_km=10))
    assert cerca in resultado and lejos not in resultado


def test_reportes_cercanos_compara_ubicacion_del_incendio_no_del_usuario(foco, crear_reporte):
    """El ciudadano puede reportar desde lejos: si su GPS está cerca del foco
    pero el pin del incendio está lejos, NO debe contar."""
    r = crear_reporte(incendio=Point(-75.0, 7.0, srid=4326), usuario=foco.ubicacion)
    assert r not in foco.reportes_cercanos(radio_km=10)


def test_reportes_cercanos_respeta_el_radio(foco, crear_reporte):
    r = crear_reporte(incendio=Point(-75.3937, 6.1552, srid=4326))  # ~2.2 km
    assert r in foco.reportes_cercanos(radio_km=10)
    assert r not in foco.reportes_cercanos(radio_km=1)
