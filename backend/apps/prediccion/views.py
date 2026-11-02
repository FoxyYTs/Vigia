from datetime import date

from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente
from apps.prediccion.serializers import ZonaRecurrenteSerializer


class ZonaRecurrenteViewSet(viewsets.ReadOnlyModelViewSet):
    """Zonas de incendio recurrente de la corrida más reciente del modelo
    (público: alimenta la capa de predicción del mapa). Parámetros opcionales:
    `mes` (AAAA-MM, por defecto el primero que predice la corrida) y
    `min_puntaje`. `meses/` lista los meses disponibles."""

    permission_classes = [AllowAny]
    serializer_class = ZonaRecurrenteSerializer

    def get_queryset(self):
        corrida = CorridaModeloML.objects.first()  # ordering = -fecha_ejecucion
        if corrida is None:
            return ZonaRecurrente.objects.none()
        qs = corrida.zonas.select_related("municipio")
        if self.action == "list":
            qs = qs.filter(mes_objetivo=self._mes(corrida))
        if minimo := self.request.query_params.get("min_puntaje"):
            try:
                qs = qs.filter(puntaje_recurrencia__gte=float(minimo))
            except ValueError:
                raise ValidationError({"min_puntaje": "Debe ser un número."}) from None
        return qs

    def _mes(self, corrida):
        texto = self.request.query_params.get("mes")
        if not texto:
            return corrida.zonas.order_by("mes_objetivo").values_list("mes_objetivo", flat=True).first()
        try:
            anio, mes = map(int, texto.split("-"))
            return date(anio, mes, 1)
        except ValueError:
            raise ValidationError({"mes": "Formato AAAA-MM."}) from None

    @action(detail=False)
    def meses(self, request):
        """Meses que predice la corrida más reciente, con sus métricas."""
        corrida = CorridaModeloML.objects.first()
        if corrida is None:
            return Response({"corrida": None, "meses": []})
        meses = corrida.zonas.order_by("mes_objetivo").values_list("mes_objetivo", flat=True).distinct()
        return Response({
            "corrida": corrida.pk,
            "fecha_ejecucion": corrida.fecha_ejecucion,
            "version_modelo": corrida.version_modelo,
            "meses": [m.strftime("%Y-%m") for m in meses],
            "metricas": corrida.metricas,
        })
