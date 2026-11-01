"""
Deforestación del IDEAM por municipio — ver Vigia-Plan-I1c-Historicos § Fase 3.

Fuente: mapas de "Cambio en la superficie cubierta por bosque natural" del
SMByC (IDEAM), un raster ERDAS por periodo anual en MAGNA-SIRGAS / Bogotá
(EPSG:3116), píxel de ~30 m. Códigos: 1 bosque estable, 2 deforestación,
3 regeneración, 4 no bosque estable, 5 sin información.

El raster nacional tiene ~2.800 millones de píxeles: se lee por bloques, se
cuentan los píxeles de deforestación en celdas de ~1 km (en la proyección
original) y cada celda se asigna al municipio que contiene su centro.
"""

import hashlib
import logging
import tempfile
from pathlib import Path

import numpy as np
import requests
from django.contrib.gis.gdal import GDALRaster
from django.db import connection, transaction

from apps.historico.models import HistoricoDeforestacion
from apps.usuarios.models import Municipio

logger = logging.getLogger(__name__)

URL_CAPAS = "https://bart.ideam.gov.co/smbyc/Cambio%20en%20la%20superficie%20cubierta%20por%20bosque%20natural/Capas/"
# Año final del periodo → (archivo, SHA-256 verificado al descargarlo el 1-nov-2026).
CATALOGO = {
    2019: ("cambio_2018_2019_v8_200707.img", "8b1c659b80cdf52acc6e97e1442b5f87e11acb80f213a167530eb3e82281ce9e"),
    2020: ("cambio_2019-2020_v8_210702.img", "0b0f64b28409dd998100f82c6b36bafd2febdda033f0430bdfada5903ffdcae8"),
    2021: ("cambio_2020_2021_v8_220710.img", "dcaee2650348fe814f44ae560f73b60b528cc067dcb3843ef1529d82aa803044"),
    2022: ("cambio_2021_2022_v8_230705.img", "2725b3c6e3467049959560b022eca81519373a54863732e747f61abdadcc8ba0"),
    2023: ("cambio_2022_2023_V8_240703.img", "461773fcd6b5613b2dff149f91a5ea61478e143727bd157571089ac8536d78a4"),
    2024: ("cambio_2023_2024_v8_250721.img", "779b1dd060f066e770230dcce3badaa30be98bde3578475baf7fa43ae55cc821"),
    2025: ("cambio_2024_2025_v8_260729.img", "774f3587b5ba6c047067d5ea7539bb9db5315e2fa37097a216da63d22fe385a9"),
}
SRID_ESPERADO = 3116
DEFORESTACION = 2
BLOQUE = 4096  # píxeles por lado: ~16 MB de uint8 por lectura
FACTOR = 33  # píxeles de 30 m por celda de agregación (~1 km)


def sha256(ruta: Path) -> str:
    h = hashlib.sha256()
    with open(ruta, "rb") as f:
        for trozo in iter(lambda: f.read(1 << 20), b""):
            h.update(trozo)
    return h.hexdigest()


def contar_por_celdas(raster: GDALRaster, codigo=DEFORESTACION, bloque=BLOQUE, factor=FACTOR):
    """Píxeles con `codigo` por celda de factor×factor píxeles. Devuelve los
    arreglos (columna, fila, conteo) de las celdas no vacías."""
    banda = raster.bands[0]
    claves = []
    for oy in range(0, raster.height, bloque):
        alto = min(bloque, raster.height - oy)
        for ox in range(0, raster.width, bloque):
            ancho = min(bloque, raster.width - ox)
            filas, cols = np.nonzero(banda.data(offset=(ox, oy), size=(ancho, alto)) == codigo)
            if len(filas):
                claves.append(((oy + filas) // factor) * (raster.width // factor + 1) + (ox + cols) // factor)
    if not claves:
        return np.array([], int), np.array([], int), np.array([], int)
    unicas, conteo = np.unique(np.concatenate(claves), return_counts=True)
    ancho_celdas = raster.width // factor + 1
    return unicas % ancho_celdas, unicas // ancho_celdas, conteo


def hectareas_por_municipio(raster: GDALRaster, factor=FACTOR, **kw) -> tuple[dict[int, float], float]:
    """{municipio_id: hectáreas deforestadas} y las hectáreas que no cayeron
    en ningún municipio (mar o borde de los polígonos simplificados)."""
    x0, ancho_px, _, y0, _, alto_px = raster.geotransform
    ha_pixel = abs(ancho_px * alto_px) / 10_000
    cols, filas, conteo = contar_por_celdas(raster, factor=factor, **kw)
    xs = x0 + (cols * factor + factor / 2) * ancho_px
    ys = y0 + (filas * factor + factor / 2) * alto_px
    sql = f"""
        SELECT m.id, sum(c.n)
        FROM unnest(%s::float8[], %s::float8[], %s::bigint[]) AS c(x, y, n)
        JOIN {Municipio._meta.db_table} m ON m.geom IS NOT NULL
         AND ST_Contains(m.geom, ST_Transform(ST_SetSRID(ST_MakePoint(c.x, c.y), %s), 4326))
        GROUP BY m.id
    """
    with connection.cursor() as cursor:
        cursor.execute(sql, [xs.tolist(), ys.tolist(), conteo.tolist(), raster.srid])
        por_municipio = {mid: float(n) * ha_pixel for mid, n in cursor.fetchall()}
    sin_municipio = float(conteo.sum()) * ha_pixel - sum(por_municipio.values())
    return por_municipio, sin_municipio


def descargar(archivo: str, sha_esperado: str, destino: Path) -> Path:
    ruta = destino / archivo
    with requests.get(URL_CAPAS + archivo, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(ruta, "wb") as f:
            for trozo in r.iter_content(1 << 20):
                f.write(trozo)
    return verificar(ruta, sha_esperado)


def verificar(ruta: Path, sha_esperado: str) -> Path:
    if (obtenido := sha256(ruta)) != sha_esperado:
        raise ValueError(f"{ruta.name}: SHA-256 {obtenido} no coincide con el esperado {sha_esperado}.")
    return ruta


def cargar_periodo(anio: int, directorio: Path | None = None) -> dict:
    """Carga el periodo (anio-1)–anio. Con `directorio` usa el archivo ya
    descargado ahí (también verifica el hash); si no, lo descarga a un
    temporal que se borra al terminar. Reemplaza lo cargado antes."""
    archivo, sha = CATALOGO[anio]
    with tempfile.TemporaryDirectory() as tmp:
        ruta = verificar(directorio / archivo, sha) if directorio else descargar(archivo, sha, Path(tmp))
        raster = GDALRaster(str(ruta))
        if raster.srid != SRID_ESPERADO:
            raise ValueError(f"{archivo}: SRID {raster.srid}, se esperaba {SRID_ESPERADO}.")
        por_municipio, sin_municipio = hectareas_por_municipio(raster)
    guardar(anio, por_municipio)
    return {
        "anio": anio,
        "municipios": len(por_municipio),
        "hectareas": round(sum(por_municipio.values()), 1),
        "hectareas_sin_municipio": round(sin_municipio, 1),
    }


@transaction.atomic
def guardar(anio: int, por_municipio: dict[int, float]) -> None:
    HistoricoDeforestacion.objects.filter(fuente=HistoricoDeforestacion.Fuente.IDEAM, anio=anio).delete()
    municipios = Municipio.objects.in_bulk(list(por_municipio))
    HistoricoDeforestacion.objects.bulk_create(
        HistoricoDeforestacion(
            fuente=HistoricoDeforestacion.Fuente.IDEAM,
            anio=anio,
            area=municipios[mid].geom,
            hectareas_afectadas=round(ha, 2),
            municipio=municipios[mid],
        )
        for mid, ha in por_municipio.items()
    )
