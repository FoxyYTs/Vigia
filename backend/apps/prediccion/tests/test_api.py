from datetime import date

import pytest
from django.contrib.gis.geos import MultiPolygon, Polygon

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente

pytestmark = pytest.mark.django_db


def _zona(corrida, puntaje, mes=date(2026, 1, 1)):
    area = MultiPolygon(Polygon(((0, 0), (0, 1), (1, 1), (1, 0), (0, 0))), srid=4326)
    return ZonaRecurrente.objects.create(
        corrida=corrida, area=area, mes_objetivo=mes, puntaje_recurrencia=puntaje, cantidad_incendios_historicos=3
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


def test_por_defecto_muestra_el_primer_mes_y_filtra_por_mes(api):
    c = CorridaModeloML.objects.create(version_modelo="v1")
    enero = _zona(c, 0.5, date(2026, 1, 1))
    febrero = _zona(c, 0.6, date(2026, 2, 1))
    assert [z["id"] for z in api.get("/api/zonas-recurrentes/").data["results"]] == [enero.id]
    r = api.get("/api/zonas-recurrentes/?mes=2026-02")
    assert [z["id"] for z in r.data["results"]] == [febrero.id]
    assert r.data["results"][0]["mes_objetivo"] == "2026-02-01"
    assert api.get("/api/zonas-recurrentes/?mes=febrero").status_code == 400


def test_meses_lista_los_meses_y_las_metricas_de_la_corrida(api):
    assert api.get("/api/zonas-recurrentes/meses/").data["meses"] == []
    c = CorridaModeloML.objects.create(version_modelo="v1", metricas={"prevalencia": 0.17})
    for mes in (date(2026, 3, 1), date(2026, 1, 1), date(2026, 2, 1)):
        _zona(c, 0.5, mes)
        _zona(c, 0.7, mes)
    r = api.get("/api/zonas-recurrentes/meses/").data
    assert r["meses"] == ["2026-01", "2026-02", "2026-03"]
    assert r["corrida"] == c.pk and r["metricas"] == {"prevalencia": 0.17}
