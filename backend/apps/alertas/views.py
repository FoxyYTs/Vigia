from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

from apps.alertas.models import Alerta
from apps.alertas.serializers import AlertaSerializer


class AlertaViewSet(viewsets.ReadOnlyModelViewSet):
    """Alertas generadas por el sistema. Solo con sesión: el mapa público
    muestra focos y zonas; las alertas llegan a usuarios registrados (y al
    canal público de Telegram)."""

    permission_classes = [IsAuthenticated]
    serializer_class = AlertaSerializer

    def get_queryset(self):
        qs = Alerta.objects.select_related("municipio")
        if self.request.user.es_ciudadano():
            # La acumulación es una sospecha pendiente de validar: va solo a
            # entidades y administradores (ver ruteo en despachador.py).
            qs = qs.exclude(tipo_disparador=Alerta.TipoDisparador.ACUMULACION_REPORTES)
        if tipo := self.request.query_params.get("tipo"):
            qs = qs.filter(tipo_disparador=tipo)
        return qs
