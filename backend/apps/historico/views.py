from django.db.models import Count, Sum
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from apps.historico.models import IncendioReportado
from apps.historico.serializers import IncendioReportadoSerializer


class IncendioReportadoViewSet(viewsets.ReadOnlyModelViewSet):
    """Incendios forestales reportados a la UNGRD (público, solo lectura).
    Filtros opcionales: `anio`, `municipio` (código DANE). `por-municipio/`
    agrega por municipio: cantidad y hectáreas."""

    permission_classes = [AllowAny]
    serializer_class = IncendioReportadoSerializer

    def get_queryset(self):
        qs = IncendioReportado.objects.select_related("municipio")
        params = self.request.query_params
        if anio := params.get("anio"):
            if not anio.isdigit():
                raise ValidationError({"anio": "Debe ser un año, p. ej. 2024."})
            qs = qs.filter(fecha__year=int(anio))
        if codigo := params.get("municipio"):
            qs = qs.filter(municipio__codigo_dane=codigo)
        return qs

    @action(detail=False, url_path="por-municipio")
    def por_municipio(self, request):
        filas = (
            self.get_queryset()
            .exclude(municipio=None)
            .values("municipio__codigo_dane", "municipio__nombre", "municipio__departamento")
            .annotate(incendios=Count("id"), hectareas=Sum("hectareas"))
            .order_by("-incendios")
        )
        return Response([
            {
                "codigo_dane": f["municipio__codigo_dane"],
                "municipio": f"{f['municipio__nombre']}, {f['municipio__departamento']}",
                "incendios": f["incendios"],
                "hectareas": f["hectareas"],
            }
            for f in filas
        ])
