from datetime import datetime, timedelta, timezone

import pytest
from django.contrib.gis.geos import Point

from apps.satelital.models import FocoIncendio

pytestmark = pytest.mark.django_db

AHORA = datetime.now(timezone.utc)


def _foco(horas_atras=1, lon=-75.37, lat=6.15, fuente=FocoIncendio.Fuente.NASA_FIRMS):
    return FocoIncendio.objects.create(
        fuente=fuente, ubicacion=Point(lon, lat, srid=4326), fecha_hora=AHORA - timedelta(hours=horas_atras)
    )


def test_focos_es_publico_y_expone_coordenadas(api):
    _foco()
    r = api.get("/api/focos/")
    assert r.status_code == 200
    f = r.data["results"][0]
    assert f["latitud"] == pytest.approx(6.15) and f["longitud"] == pytest.approx(-75.37)


def test_por_defecto_solo_las_ultimas_48_horas(api):
    reciente, viejo = _foco(horas_atras=2), _foco(horas_atras=24 * 10)
    ids = {f["id"] for f in api.get("/api/focos/").data["results"]}
    assert reciente.id in ids and viejo.id not in ids


def test_rango_explicito_de_fechas(api):
    viejo = _foco(horas_atras=24 * 10)
    desde = (AHORA - timedelta(days=11)).date().isoformat()
    hasta = (AHORA - timedelta(days=9)).date().isoformat()
    ids = {f["id"] for f in api.get(f"/api/focos/?desde={desde}&hasta={hasta}").data["results"]}
    assert ids == {viejo.id}


def test_rango_mayor_a_31_dias_se_rechaza(api):
    r = api.get("/api/focos/?desde=2026-01-01&hasta=2026-09-01")
    assert r.status_code == 400 and "desde" in r.data


@pytest.mark.parametrize("consulta", ["desde=ayer", "fuente=OTRA", "bbox=1,2,3", "bbox=a,b,c,d"])
def test_parametros_invalidos_devuelven_400(api, consulta):
    assert api.get(f"/api/focos/?{consulta}").status_code == 400


def test_filtro_por_fuente(api):
    firms, inpe = _foco(), _foco(fuente=FocoIncendio.Fuente.INPE_QUEIMADAS)
    r = api.get("/api/focos/?fuente=INPE_QUEIMADAS")
    assert {f["id"] for f in r.data["results"]} == {inpe.id}


def test_filtro_por_bbox(api):
    dentro, fuera = _foco(lon=-75.4, lat=6.1), _foco(lon=-66.0, lat=10.0)
    r = api.get("/api/focos/?bbox=-76,5,-75,7")
    assert {f["id"] for f in r.data["results"]} == {dentro.id}


def test_los_focos_vienen_paginados(api):
    for i in range(3):
        _foco(lon=-75.37 - i * 0.01)  # el mismo punto y hora no puede repetirse
    r = api.get("/api/focos/?page_size=2")
    assert r.data["count"] == 3 and len(r.data["results"]) == 2 and r.data["next"]


def test_focos_no_se_escribe_por_la_api(api_como, administrador):
    assert api_como(administrador).post("/api/focos/", {}).status_code == 405
