import pytest
from django.contrib.gis.geos import MultiPolygon, Polygon

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente

pytestmark = pytest.mark.django_db


def _zona(corrida, puntaje):
    area = MultiPolygon(Polygon(((0, 0), (0, 1), (1, 1), (1, 0), (0, 0))), srid=4326)
    return ZonaRecurrente.objects.create(
        corrida=corrida, area=area, puntaje_recurrencia=puntaje, cantidad_incendios_historicos=3
    )


def test_sin_corridas_devuelve_lista_vacia(api):
    r = api.get("/api/zonas-recurrentes/")
    assert r.status_code == 200 and r.data["results"] == []


def test_solo_muestra_la_corrida_mas_reciente(api):
    from datetime import timedelta

    from django.utils import timezone

    vieja = CorridaModeloML.objects.create(version_modelo="v1", fecha_ejecucion=timezone.now() - timedelta(days=30))
    nueva = CorridaModeloML.objects.create(version_modelo="v2")
    _zona(vieja, 0.3)
    z = _zona(nueva, 0.9)
    r = api.get("/api/zonas-recurrentes/")
    assert [x["id"] for x in r.data["results"]] == [z.id]


def test_la_geometria_sale_como_geojson(api):
    _zona(CorridaModeloML.objects.create(version_modelo="v1"), 0.5)
    area = api.get("/api/zonas-recurrentes/").data["results"][0]["area"]
    assert area["type"] == "MultiPolygon" and area["coordinates"]


def test_filtro_por_puntaje_minimo(api):
    c = CorridaModeloML.objects.create(version_modelo="v1")
    _zona(c, 0.2)
    alta = _zona(c, 0.8)
    assert [z["id"] for z in api.get("/api/zonas-recurrentes/?min_puntaje=0.5").data["results"]] == [alta.id]
    assert api.get("/api/zonas-recurrentes/?min_puntaje=mucho").status_code == 400
