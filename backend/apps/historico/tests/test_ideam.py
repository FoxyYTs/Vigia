"""Carga de la deforestación del IDEAM con un raster sintético pequeño en la
misma proyección que el real (EPSG:3116, píxeles de 30 m)."""

from pathlib import Path
from unittest.mock import patch

import numpy as np
import pytest
from django.contrib.gis.gdal import GDALRaster
from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from django.core.management import CommandError, call_command

from apps.historico import ideam
from apps.historico.models import HistoricoDeforestacion
from apps.usuarios.models import Municipio

pytestmark = pytest.mark.django_db

ARCHIVO = "cambio_prueba.img"
PIXEL = 30.0


def _raster(ruta: Path) -> Path:
    """200×200 píxeles alrededor de Rionegro: 100 de deforestación (código 2)
    en el cuadrante superior izquierdo y 40 en el inferior derecho."""
    centro = Point(-75.3737, 6.1552, srid=4326)
    centro.transform(3116)
    datos = np.full((200, 200), 1, dtype=np.uint8)
    datos[10:20, 10:20] = 2
    datos[150:154, 150:160] = 2
    GDALRaster({
        "driver": "GTiff", "name": str(ruta), "srid": 3116, "width": 200, "height": 200,
        "origin": (centro.x - 3000, centro.y + 3000), "scale": (PIXEL, -PIXEL),
        "datatype": 1, "bands": [{"data": datos.ravel().tolist()}],
    }).bands[0].data()  # fuerza la escritura
    return ruta


def _cuadro(x0, y0, x1, y1):
    return MultiPolygon(Polygon(((x0, y0), (x0, y1), (x1, y1), (x1, y0), (x0, y0))), srid=4326)


@pytest.fixture
def municipios():
    """El oeste (x < centro) es Rionegro; el este, Marinilla. Mitades en 4326."""
    oeste = _cuadro(-75.45, 6.08, -75.3737, 6.23)
    este = _cuadro(-75.3737, 6.08, -75.30, 6.23)
    return (
        Municipio.objects.create(nombre="Rionegro", departamento="Antioquia", codigo_dane="05615", geom=oeste),
        Municipio.objects.create(nombre="Marinilla", departamento="Antioquia", codigo_dane="05440", geom=este),
    )


@pytest.fixture
def catalogo(tmp_path):
    ruta = _raster(tmp_path / ARCHIVO)
    with patch.dict(ideam.CATALOGO, {2030: (ARCHIVO, ideam.sha256(ruta))}, clear=True):
        yield tmp_path


def test_contar_por_celdas_agrega_los_pixeles_de_deforestacion(catalogo):
    cols, filas, conteo = ideam.contar_por_celdas(GDALRaster(str(catalogo / ARCHIVO)), bloque=64, factor=50)
    assert conteo.sum() == 140
    assert sorted(zip(cols.tolist(), filas.tolist(), conteo.tolist(), strict=True)) == [(0, 0, 100), (3, 3, 40)]


def test_cargar_periodo_asigna_hectareas_a_cada_municipio(catalogo, municipios):
    rionegro, marinilla = municipios
    r = ideam.cargar_periodo(2030, directorio=catalogo)

    ha_pixel = PIXEL * PIXEL / 10_000
    assert r["hectareas"] == pytest.approx(140 * ha_pixel, abs=0.1)
    filas = {h.municipio_id: h for h in HistoricoDeforestacion.objects.all()}
    assert filas[rionegro.pk].hectareas_afectadas == pytest.approx(100 * ha_pixel)
    assert filas[marinilla.pk].hectareas_afectadas == pytest.approx(40 * ha_pixel)
    assert filas[rionegro.pk].area == rionegro.geom and filas[rionegro.pk].anio == 2030


def test_repetir_la_carga_reemplaza_el_periodo(catalogo, municipios):
    ideam.cargar_periodo(2030, directorio=catalogo)
    ideam.cargar_periodo(2030, directorio=catalogo)
    assert HistoricoDeforestacion.objects.count() == 2


def test_hash_distinto_aborta_sin_cargar(catalogo, municipios):
    with patch.dict(ideam.CATALOGO, {2030: (ARCHIVO, "0" * 64)}), pytest.raises(ValueError, match="SHA-256"):
        ideam.cargar_periodo(2030, directorio=catalogo)
    assert not HistoricoDeforestacion.objects.exists()


def test_comando(catalogo, municipios, capsys):
    call_command("cargar_deforestacion_ideam", "2030", directorio=catalogo)
    assert "2029–2030: 13 ha en 2 municipios" in capsys.readouterr().out
    with pytest.raises(CommandError, match="1999"):
        call_command("cargar_deforestacion_ideam", "1999", directorio=catalogo)


def test_raster_sin_deforestacion_no_cuenta_nada(tmp_path):
    ruta = tmp_path / "vacio.tif"
    GDALRaster({
        "driver": "GTiff", "name": str(ruta), "srid": 3116, "width": 10, "height": 10,
        "origin": (0, 0), "scale": (PIXEL, -PIXEL), "datatype": 1, "bands": [{"data": [1] * 100}],
    }).bands[0].data()
    assert all(len(a) == 0 for a in ideam.contar_por_celdas(GDALRaster(str(ruta))))


def test_otra_proyeccion_se_rechaza(tmp_path, municipios):
    ruta = tmp_path / ARCHIVO
    GDALRaster({
        "driver": "GTiff", "name": str(ruta), "srid": 4326, "width": 10, "height": 10,
        "origin": (-75.4, 6.2), "scale": (0.001, -0.001), "datatype": 1, "bands": [{"data": [2] * 100}],
    }).bands[0].data()
    with patch.dict(ideam.CATALOGO, {2030: (ARCHIVO, ideam.sha256(ruta))}), pytest.raises(ValueError, match="SRID"):
        ideam.cargar_periodo(2030, directorio=tmp_path)


def test_descarga_el_raster_y_verifica_el_hash(catalogo, municipios):
    import responses

    contenido = (catalogo / ARCHIVO).read_bytes()
    with responses.RequestsMock() as rsps:
        rsps.get(ideam.URL_CAPAS + ARCHIVO, body=contenido)
        assert ideam.cargar_periodo(2030)["municipios"] == 2
