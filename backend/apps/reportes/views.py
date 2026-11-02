from django.contrib.gis.db.models import PointField
from django.db.models import Exists, F, Func, OuterRef
from django.http import Http404, HttpResponse
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from apps.alertas.motor import MotorAlertas
from apps.reportes.models import ReporteCiudadano
from apps.reportes.serializers import ReporteCiudadanoSerializer
from apps.usuarios.models import Municipio
from apps.usuarios.permissions import EsAdministrador, EsCiudadano, EsStaff


class ReporteCiudadanoViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """
    Ciudadano: crea reportes y consulta los suyos.
    Administrador: consulta y valida o rechaza los reportes cuyo incendio cae
    en la jurisdicción de su entidad (municipios con polígono). Sin entidad, o
    con una entidad sin polígonos cargados, es un administrador nacional y ve
    todos. Fuera de su jurisdicción el reporte responde 404.
    Staff: consulta todos (solo lectura, para revisarlos); no crea ni resuelve.
    """

    serializer_class = ReporteCiudadanoSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "reporte"

    def get_throttles(self):
        # Solo crear reportes tiene límite: consultar y validar no, o un
        # administrador quedaba bloqueado tras 30 consultas en una hora.
        return super().get_throttles() if self.action == "create" else []

    def get_permissions(self):
        if self.action == "create":
            return [EsCiudadano()]
        if self.action in ("validar", "rechazar"):
            return [EsAdministrador()]
        return [(EsCiudadano | EsAdministrador | EsStaff)()]

    def get_queryset(self):
        usuario = self.request.user
        qs = ReporteCiudadano.objects.select_related("ciudadano", "validado_por")
        if usuario.es_ciudadano():
            qs = qs.filter(ciudadano=usuario)
        elif usuario.es_administrador() and usuario.entidad_id:
            jurisdiccion = Municipio.objects.filter(entidades=usuario.entidad_id, geom__isnull=False)
            if jurisdiccion.exists():
                qs = qs.annotate(punto=_como_geometry("ubicacion_incendio")).filter(
                    Exists(jurisdiccion.filter(geom__contains=OuterRef("punto")))
                )
        if estado := self.request.query_params.get("estado"):
            qs = qs.filter(estado=estado)
        return qs

    def perform_create(self, serializer):
        reporte = serializer.save(ciudadano=self.request.user)
        MotorAlertas().evaluar_reporte_nuevo(reporte)

    def _resolver(self, request, accion):
        reporte = self.get_object()
        try:
            getattr(reporte, accion)(request.user)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_409_CONFLICT)
        if accion == "validar":
            MotorAlertas().evaluar_validacion_manual(reporte)
        return Response(self.get_serializer(reporte).data)

    @action(detail=True, url_path="foto", url_name="foto")
    def foto(self, request, pk=None):
        """La foto (o `?miniatura=1`) con los mismos permisos que el reporte.
        Nginx la entrega desde una ruta `internal` que no es accesible desde
        afuera: /media/ ya no es público."""
        reporte = self.get_object()
        archivo = reporte.miniatura if request.query_params.get("miniatura") else reporte.foto
        if not archivo:
            raise Http404("La foto ya no está disponible.")
        respuesta = HttpResponse(content_type="image/jpeg")
        respuesta["X-Accel-Redirect"] = f"/protegido/media/{archivo.name}"
        respuesta["Cache-Control"] = "private, max-age=3600"
        return respuesta

    @action(detail=True, methods=["post"])
    def validar(self, request, pk=None):
        return self._resolver(request, "validar")

    @action(detail=True, methods=["post"])
    def rechazar(self, request, pk=None):
        return self._resolver(request, "rechazar")


def _como_geometry(campo):
    """geography → geometry: `Municipio.geom` es geometry y PostGIS no
    compara directamente ambos tipos."""
    return Func(F(campo), template="%(expressions)s::geometry", output_field=PointField(srid=4326))
