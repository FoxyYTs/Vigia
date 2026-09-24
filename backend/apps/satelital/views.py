from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

from django.contrib.gis.geos import Polygon
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework import viewsets
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny

from apps.satelital.models import FocoIncendio
from apps.satelital.serializers import FocoIncendioSerializer

# La tabla acumula millones de focos (histórico): sin ventana de tiempo, una
# consulta pública podría intentar recorrerlos todos.
VENTANA_POR_DEFECTO = timedelta(hours=48)
VENTANA_MAXIMA = timedelta(days=31)


def _fecha(valor: str, nombre: str, fin_de_dia: bool = False):
    """Acepta '2026-09-01' o '2026-09-01T12:00:00Z'. Una fecha sin hora es el
    inicio del día, o el final si `fin_de_dia` (para que `hasta=2026-09-01`
    incluya los focos de ese día)."""
    resultado = parse_datetime(valor)
    if resultado is None:
        dia = parse_date(valor)
        if dia is None:
            raise ValidationError({nombre: "Formato inválido, usar AAAA-MM-DD o ISO 8601."})
        resultado = datetime(dia.year, dia.month, dia.day) + (timedelta(days=1) if fin_de_dia else timedelta())
    if timezone.is_naive(resultado):
        resultado = timezone.make_aware(resultado, dt_timezone.utc)
    return resultado


class FocoIncendioViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Focos satelitales para el mapa (público, sin sesión).

    Parámetros: `desde`, `hasta` (por defecto, las últimas 48 h; máximo 31
    días de rango), `fuente` (NASA_FIRMS / INPE_QUEIMADAS) y `bbox`
    (oeste,sur,este,norte).
    """

    permission_classes = [AllowAny]
    serializer_class = FocoIncendioSerializer

    def get_queryset(self):
        params = self.request.query_params
        hasta = _fecha(params["hasta"], "hasta", fin_de_dia=True) if "hasta" in params else timezone.now()
        desde = _fecha(params["desde"], "desde") if "desde" in params else hasta - VENTANA_POR_DEFECTO
        if desde > hasta:
            raise ValidationError({"desde": "No puede ser posterior a `hasta`."})
        if hasta - desde > VENTANA_MAXIMA:
            raise ValidationError({"desde": "El rango máximo es de 31 días."})

        qs = FocoIncendio.objects.filter(fecha_hora__gte=desde, fecha_hora__lte=hasta)

        if fuente := params.get("fuente"):
            if fuente not in FocoIncendio.Fuente.values:
                raise ValidationError({"fuente": f"Valores válidos: {', '.join(FocoIncendio.Fuente.values)}."})
            qs = qs.filter(fuente=fuente)

        if bbox := params.get("bbox"):
            try:
                oeste, sur, este, norte = (float(v) for v in bbox.split(","))
            except ValueError:
                raise ValidationError({"bbox": "Formato: oeste,sur,este,norte (4 números)."}) from None
            qs = qs.filter(ubicacion__intersects=Polygon.from_bbox((oeste, sur, este, norte)))

        return qs.order_by("-fecha_hora")
