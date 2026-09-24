from django.utils import timezone
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.notificaciones.models import Notificacion
from apps.notificaciones.serializers import NotificacionSerializer


class NotificacionViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Bandeja del usuario: solo ve sus propias notificaciones."""

    permission_classes = [IsAuthenticated]
    serializer_class = NotificacionSerializer

    def get_queryset(self):
        return Notificacion.objects.filter(usuario=self.request.user)

    @action(detail=True, methods=["post"], url_path="marcar-leida")
    def marcar_leida(self, request, pk=None):
        n = self.get_object()
        if n.estado != Notificacion.Estado.LEIDO:
            n.estado = Notificacion.Estado.LEIDO
            n.fecha_lectura = timezone.now()
            n.save(update_fields=["estado", "fecha_lectura"])
        return Response(self.get_serializer(n).data)
