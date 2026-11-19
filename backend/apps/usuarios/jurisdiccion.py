"""
Jurisdicción de un administrador: los municipios con polígono de su entidad.
Sin entidad, o con una entidad sin polígonos cargados, es un administrador
nacional. La comparten los reportes ciudadanos, las estadísticas y los
informes, para que el mismo administrador vea el mismo alcance en todos.
"""

from django.contrib.gis.db.models import PointField
from django.db.models import Exists, F, Func, OuterRef

from apps.usuarios.models import Municipio


def municipios_de(usuario):
    """Municipios con polígono de la entidad del administrador, o None si ve
    todo el país (staff, ciudadano, o administrador sin entidad o sin polígonos)."""
    if not (usuario.es_administrador() and usuario.entidad_id):
        return None
    municipios = Municipio.objects.filter(entidades=usuario.entidad_id, geom__isnull=False)
    return municipios if municipios.exists() else None


def como_geometry(campo):
    """geography → geometry: `Municipio.geom` es geometry y PostGIS no
    compara directamente ambos tipos."""
    return Func(F(campo), template="%(expressions)s::geometry", output_field=PointField(srid=4326))


def dentro_de(municipios, campo):
    """Condición: el punto `campo` (geometry) cae en alguno de [municipios]."""
    return Exists(municipios.filter(geom__contains=OuterRef(campo)))
