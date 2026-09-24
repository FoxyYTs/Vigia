"""
Contorno de Colombia para descartar focos que caen en otros países.

FIRMS se consulta con un rectángulo (COLOMBIA_BBOX) que también cubre
Venezuela, Brasil, Perú, Ecuador, Panamá y mar: con los datos reales, solo el
42,6 % de los focos del rectángulo están dentro de Colombia. Sin este filtro,
una alerta podría dispararse por un incendio en Venezuela.

El contorno es aproximado (ver data/LICENCIA.md) y se ensancha
TOLERANCIA_GRADOS (~1 km) para no perder detecciones legítimas en la costa o la
frontera por el error de simplificación del polígono.
"""

from functools import lru_cache
from pathlib import Path

from django.contrib.gis.geos import GEOSGeometry, Point

RUTA_CONTORNO = Path(__file__).parent / "data" / "colombia.geojson"
TOLERANCIA_GRADOS = 0.01


@lru_cache(maxsize=1)
def contorno_colombia() -> GEOSGeometry:
    """Polígono de Colombia ensanchado por la tolerancia (se carga una vez)."""
    return GEOSGeometry(RUTA_CONTORNO.read_text(), srid=4326).buffer(TOLERANCIA_GRADOS)


@lru_cache(maxsize=1)
def _contorno_preparado():
    # La versión "preparada" indexa el polígono: hace rápidas las millones de
    # consultas punto-en-polígono del histórico.
    return contorno_colombia().prepared


def esta_en_colombia(longitud: float, latitud: float) -> bool:
    return _contorno_preparado().intersects(Point(longitud, latitud, srid=4326))
