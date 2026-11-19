from datetime import UTC, date, datetime, timedelta

import pytest
from django.contrib.gis.geos import MultiPolygon, Point, Polygon

from apps.alertas.models import Alerta
from conftest import RIONEGRO
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import EntidadPublica, Municipio

pytestmark = pytest.mark.django_db

PERIODO = "?desde=2026-09-01&hasta=2026-09-30"
CUCUTA = Point(-72.50, 7.89, srid=4326)


def _cuadro(lon, lat):
    return MultiPolygon(Polygon.from_bbox((lon - 0.1, lat - 0.1, lon + 0.1, lat + 0.1)), srid=4326)


def _foco(punto, dia, fuente=FocoIncendio.Fuente.NASA_FIRMS):
    return FocoIncendio.objects.create(
        fuente=fuente, ubicacion=punto, fecha_hora=datetime(2026, 9, dia, 15, 0, tzinfo=UTC), confianza="n"
    )


@pytest.fixture
def datos(municipio, crear_reporte):
    """Rionegro (Antioquia) y Cúcuta (Norte de Santander), ambos con polígono."""
    municipio.geom = _cuadro(RIONEGRO.x, RIONEGRO.y)
    municipio.save()
    cucuta = Municipio.objects.create(
        nombre="Cúcuta", departamento="Norte de Santander", geom=_cuadro(CUCUTA.x, CUCUTA.y)
    )
    _foco(RIONEGRO, 2)
    _foco(RIONEGRO, 2, FocoIncendio.Fuente.INPE_QUEIMADAS)
    _foco(CUCUTA, 3)
    _foco(CUCUTA, 15)
    _foco(CUCUTA, 15, FocoIncendio.Fuente.INPE_QUEIMADAS)
    _foco(RIONEGRO, 30)
    # Fuera del periodo: 1 de octubre en Colombia.
    FocoIncendio.objects.create(
        fuente=FocoIncendio.Fuente.NASA_FIRMS, ubicacion=RIONEGRO,
        fecha_hora=datetime(2026, 10, 1, 6, 0, tzinfo=UTC), confianza="n",
    )
    satelital = Alerta.TipoDisparador.DETECCION_SATELITAL
    for m in (municipio, cucuta):
        Alerta.objects.create(tipo_disparador=satelital, ubicacion=RIONEGRO, municipio=m)
    crear_reporte()
    crear_reporte(incendio=CUCUTA, estado=ReporteCiudadano.Estado.RECHAZADO)
    # fecha_creacion es auto_now_add: se mueve al periodo consultado.
    septiembre = datetime(2026, 9, 10, 15, 0, tzinfo=UTC)
    Alerta.objects.update(fecha_creacion=septiembre)
    ReporteCiudadano.objects.update(fecha_creacion=septiembre)
    return cucuta


def test_staff_ve_todo_el_pais(api_como, staff, datos):
    r = api_como(staff).get(f"/api/estadisticas/{PERIODO}")
    assert r.status_code == 200
    focos = r.data["focos"]
    assert r.data["nacional"] is True
    assert focos["total"] == 6
    assert focos["por_fuente"] == [{"clave": "NASA_FIRMS", "cantidad": 4}, {"clave": "INPE_QUEIMADAS", "cantidad": 2}]
    assert focos["por_departamento"] == [
        {"clave": "Antioquia", "cantidad": 3},
        {"clave": "Norte de Santander", "cantidad": 3},
    ]
    por_dia = {str(d["dia"]): d["cantidad"] for d in focos["por_dia"] if d["cantidad"]}
    assert por_dia == {"2026-09-02": 2, "2026-09-03": 1, "2026-09-15": 2, "2026-09-30": 1}
    # Los días sin focos también van, con 0, para que el gráfico no junte días.
    assert len(focos["por_dia"]) == 30 and focos["por_dia"][0] == {"dia": date(2026, 9, 1), "cantidad": 0}
    assert r.data["alertas"]["total"] == 2
    assert r.data["reportes"]["total"] == 2


def test_el_administrador_solo_ve_su_jurisdiccion(api_como, administrador, datos):
    r = api_como(administrador).get(f"/api/estadisticas/{PERIODO}")
    assert r.status_code == 200
    assert r.data["nacional"] is False
    assert r.data["focos"]["total"] == 3
    assert r.data["focos"]["por_departamento"] == [{"clave": "Antioquia", "cantidad": 3}]
    assert r.data["alertas"]["por_departamento"] == [{"clave": "Antioquia", "cantidad": 1}]
    assert r.data["reportes"]["por_estado"] == [{"clave": "pendiente", "cantidad": 1}]


def test_administrador_sin_poligonos_es_nacional(api_como, administrador, datos):
    otra = EntidadPublica.objects.create(nombre="Sin polígonos")
    otra.municipios.add(Municipio.objects.create(nombre="Sin geom", departamento="Meta"))
    administrador.entidad = otra
    administrador.save()
    r = api_como(administrador).get(f"/api/estadisticas/{PERIODO}")
    assert r.data["nacional"] is True and r.data["focos"]["total"] == 6


def test_ciudadano_y_anonimo_no_tienen_acceso(api, api_como, ciudadano):
    assert api.get("/api/estadisticas/").status_code == 401
    assert api_como(ciudadano).get("/api/estadisticas/").status_code == 403


@pytest.mark.parametrize(
    "consulta",
    ["?desde=2026-09-30&hasta=2026-09-01", "?desde=2025-01-01&hasta=2026-09-01", "?desde=ayer"],
)
def test_periodo_invalido(api_como, staff, consulta):
    r = api_como(staff).get(f"/api/estadisticas/{consulta}")
    assert r.status_code == 400 and "desde" in r.data


def test_periodo_por_defecto_son_30_dias(api_como, staff):
    r = api_como(staff).get("/api/estadisticas/")
    assert r.status_code == 200
    assert (r.data["hasta"] - r.data["desde"]).days == 29


@pytest.mark.parametrize("hasta", ["9999-12-31", "2999-01-01"])
def test_fecha_futura(api_como, staff, hasta):
    r = api_como(staff).get(f"/api/estadisticas/?desde=2026-09-01&hasta={hasta}")
    assert r.status_code == 400 and "hasta" in r.data


def test_un_dia_de_margen_por_el_huso_horario(api_como, staff):
    from django.utils import timezone

    manana = timezone.localdate() + timedelta(days=1)
    assert api_como(staff).get(f"/api/estadisticas/?hasta={manana}").status_code == 200
