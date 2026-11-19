from datetime import date, datetime, UTC
from unittest import mock

import pytest
from django.contrib.gis.geos import MultiPolygon, Polygon

from apps.historico.models import HistoricoDeforestacion, IncendioReportado
from apps.satelital.models import FocoIncendio
from conftest import RIONEGRO

pytestmark = pytest.mark.django_db


@pytest.fixture
def datos(municipio):
    for codigo, fecha, municipio_, ha in [
        ("1", date(2023, 2, 1), municipio, 10.0),
        ("2", date(2023, 3, 1), None, None),
        ("3", date(2024, 1, 5), municipio, 2.5),
    ]:
        IncendioReportado.objects.create(
            dataset="d", codigo=codigo, fecha=fecha, evento="INCENDIO FORESTAL", municipio=municipio_, hectareas=ha
        )
    HistoricoDeforestacion.objects.create(
        fuente="IDEAM", anio=2022, hectareas_afectadas=40.0, municipio=municipio,
        area=MultiPolygon(Polygon.from_bbox((-75.5, 6.0, -75.2, 6.3)), srid=4326),
    )
    for anio, mes, fuente in [(2020, 3, "NASA_FIRMS"), (2020, 4, "NASA_FIRMS"), (2021, 3, "NASA_FIRMS"),
                              (2021, 3, "INPE_QUEIMADAS")]:
        FocoIncendio.objects.create(
            fuente=fuente, ubicacion=RIONEGRO, fecha_hora=datetime(anio, mes, 1, tzinfo=UTC), confianza="n"
        )


def test_resumen_por_fuente_y_anio(api_como, administrador, datos):
    r = api_como(administrador).get("/api/historico/resumen/")
    assert r.status_code == 200
    ungrd, ideam, firms = r.data["ungrd"], r.data["ideam"], r.data["firms"]
    assert ungrd["total"] == 3 and ungrd["sin_municipio"] == 1
    assert (ungrd["desde"], ungrd["hasta"]) == (date(2023, 2, 1), date(2024, 1, 5))
    assert ungrd["por_anio"] == [
        {"anio": 2023, "cantidad": 2, "hectareas": 10.0},
        {"anio": 2024, "cantidad": 1, "hectareas": 2.5},
    ]
    assert ideam["por_anio"] == [{"anio": 2022, "municipios": 1, "hectareas": 40.0}]
    # Solo FIRMS: INPE no tiene archivo histórico.
    assert firms["total"] == 3
    assert firms["por_anio"] == [{"anio": 2020, "cantidad": 2}, {"anio": 2021, "cantidad": 1}]


def test_resumen_vacio(api_como, staff):
    r = api_como(staff).get("/api/historico/resumen/")
    assert r.data["ungrd"]["total"] == 0 and r.data["ungrd"]["desde"] is None
    assert r.data["ideam"]["por_anio"] == [] and r.data["firms"]["por_anio"] == []


def test_ciudadano_y_anonimo_no_ven_el_resumen(api, api_como, ciudadano):
    assert api.get("/api/historico/resumen/").status_code == 401
    assert api_como(ciudadano).get("/api/historico/resumen/").status_code == 403


@mock.patch("apps.historico.views.sincronizar_ungrd.delay")
def test_solo_el_staff_actualiza_la_ungrd(delay, api_como, staff, administrador):
    assert api_como(administrador).post("/api/historico/ungrd/sincronizar/").status_code == 403
    delay.assert_not_called()
    assert api_como(staff).post("/api/historico/ungrd/sincronizar/").status_code == 202
    delay.assert_called_once_with()


def test_la_tarea_usa_el_cliente_ungrd():
    from apps.historico.tasks import sincronizar_ungrd

    with mock.patch("apps.historico.tasks.ClienteUngrd") as cliente:
        cliente.return_value.sincronizar.return_value = 7
        assert sincronizar_ungrd() == 7
