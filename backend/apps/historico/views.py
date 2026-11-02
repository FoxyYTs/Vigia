import re

from django.db.models import Count, Sum
from rest_framework import viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from apps.historico.models import HistoricoDeforestacion, IncendioReportado
from apps.historico.serializers import IncendioReportadoSerializer


def _anio(texto: str) -> int:
    """Año de 4 dígitos ASCII entre 1900 y 2100. `isdigit()` aceptaba "²" y
    "10000", que terminaban en un error 500."""
    if not re.fullmatch(r"[0-9]{4}", texto) or not 1900 <= int(texto) <= 2100:
        raise ValidationError({"anio": "Debe ser un año, p. ej. 2024."})
    return int(texto)


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
            qs = qs.filter(fecha__year=_anio(anio))
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


# Indicadores de la capa "Histórico" del mapa: valor por municipio y año.
INDICADORES = {
    "incendios_ungrd": lambda anio: IncendioReportado.objects.filter(fecha__year=anio)
    .exclude(municipio=None)
    .values("municipio__codigo_dane")
    .annotate(valor=Count("id")),
    "deforestacion_ideam": lambda anio: HistoricoDeforestacion.objects.filter(anio=anio)
    .exclude(municipio=None)
    .values("municipio__codigo_dane")
    .annotate(valor=Sum("hectareas_afectadas")),
}


@api_view(["GET"])
@permission_classes([AllowAny])
def capa_historica(request):
    """`?indicador=incendios_ungrd|deforestacion_ideam&anio=AAAA` → valor por
    municipio (código DANE). Incendios: cantidad; deforestación: hectáreas."""
    indicador = request.query_params.get("indicador")
    anio = request.query_params.get("anio", "")
    if indicador not in INDICADORES:
        raise ValidationError({"indicador": f"Uno de: {', '.join(INDICADORES)}."})
    anio = _anio(anio)
    return Response([
        {"codigo_dane": f["municipio__codigo_dane"], "valor": round(float(f["valor"]), 2)}
        for f in INDICADORES[indicador](anio)
    ])


@api_view(["GET"])
@permission_classes([AllowAny])
def capa_historica_disponible(request):
    """Años con datos de cada indicador."""
    return Response({
        "incendios_ungrd": sorted(
            d.year for d in IncendioReportado.objects.dates("fecha", "year")
        ),
        "deforestacion_ideam": list(
            HistoricoDeforestacion.objects.order_by("anio").values_list("anio", flat=True).distinct()
        ),
    })
