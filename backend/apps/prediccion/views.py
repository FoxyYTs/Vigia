from rest_framework import viewsets
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente
from apps.prediccion.serializers import ZonaRecurrenteSerializer


class ZonaRecurrenteViewSet(viewsets.ReadOnlyModelViewSet):
    """Zonas de incendio recurrente de la corrida más reciente del modelo
    (público: alimenta la capa de predicción del mapa). Parámetro opcional:
    `min_puntaje`."""

    permission_classes = [AllowAny]
    serializer_class = ZonaRecurrenteSerializer

    def get_queryset(self):
        corrida = CorridaModeloML.objects.first()  # ordering = -fecha_ejecucion
        if corrida is None:
            return ZonaRecurrente.objects.none()
        qs = corrida.zonas.select_related("municipio")
        if minimo := self.request.query_params.get("min_puntaje"):
            try:
                qs = qs.filter(puntaje_recurrencia__gte=float(minimo))
            except ValueError:
                raise ValidationError({"min_puntaje": "Debe ser un número."}) from None
        return qs
