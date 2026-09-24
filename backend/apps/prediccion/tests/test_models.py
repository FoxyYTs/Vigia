import pytest
from django.contrib.gis.geos import MultiPolygon, Polygon

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente

pytestmark = pytest.mark.django_db


def _zona(corrida, puntaje):
    area = MultiPolygon(Polygon(((0, 0), (0, 1), (1, 1), (1, 0), (0, 0))), srid=4326)
    return ZonaRecurrente.objects.create(
        corrida=corrida, area=area, puntaje_recurrencia=puntaje, cantidad_incendios_historicos=5
    )


def test_corrida_conserva_historial_de_zonas_por_corrida():
    c1 = CorridaModeloML.objects.create(version_modelo="v1")
    c2 = CorridaModeloML.objects.create(version_modelo="v2")
    _zona(c1, 0.4)
    _zona(c2, 0.9)
    assert c1.zonas.count() == 1 and c2.zonas.count() == 1


def test_zonas_ordenadas_por_puntaje_descendente():
    c = CorridaModeloML.objects.create(version_modelo="v1")
    _zona(c, 0.2)
    _zona(c, 0.8)
    assert [z.puntaje_recurrencia for z in c.zonas.all()] == [0.8, 0.2]


def test_borrar_corrida_borra_sus_zonas():
    c = CorridaModeloML.objects.create(version_modelo="v1")
    _zona(c, 0.5)
    c.delete()
    assert ZonaRecurrente.objects.count() == 0


def test_fecha_de_ejecucion_por_defecto():
    assert CorridaModeloML.objects.create(version_modelo="v1").fecha_ejecucion is not None
