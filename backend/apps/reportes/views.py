from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from apps.reportes.models import ReporteCiudadano
from apps.reportes.serializers import ReporteCiudadanoSerializer
from apps.usuarios.permissions import EsAdministrador, EsCiudadano


class ReporteCiudadanoViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """
    Ciudadano: crea reportes y consulta los suyos.
    Administrador: consulta todos y los valida o rechaza.

    NOTA: aún no se filtra por la jurisdicción de la entidad del
    administrador — requiere la geometría de `Municipio`, que todavía no está
    cargada. Por ahora un administrador ve todos los reportes.
    """

    serializer_class = ReporteCiudadanoSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "reporte"

    def get_permissions(self):
        if self.action == "create":
            return [EsCiudadano()]
        if self.action in ("validar", "rechazar"):
            return [EsAdministrador()]
        return [(EsCiudadano | EsAdministrador)()]

    def get_queryset(self):
        usuario = self.request.user
        qs = ReporteCiudadano.objects.select_related("ciudadano", "validado_por")
        if usuario.es_ciudadano():
            qs = qs.filter(ciudadano=usuario)
        if estado := self.request.query_params.get("estado"):
            qs = qs.filter(estado=estado)
        return qs

    def perform_create(self, serializer):
        serializer.save(ciudadano=self.request.user)

    def _resolver(self, request, accion):
        reporte = self.get_object()
        try:
            getattr(reporte, accion)(request.user)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_409_CONFLICT)
        return Response(self.get_serializer(reporte).data)

    @action(detail=True, methods=["post"])
    def validar(self, request, pk=None):
        return self._resolver(request, "validar")

    @action(detail=True, methods=["post"])
    def rechazar(self, request, pk=None):
        return self._resolver(request, "rechazar")
