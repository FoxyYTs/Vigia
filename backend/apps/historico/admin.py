from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from apps.historico.models import HistoricoDeforestacion, IncendioReportado


@admin.register(HistoricoDeforestacion)
class HistoricoDeforestacionAdmin(GISModelAdmin):
    list_display = ("fuente", "anio", "hectareas_afectadas", "municipio")
    list_filter = ("fuente", "anio")
    list_select_related = ("municipio",)
    raw_id_fields = ("municipio",)

    def get_queryset(self, request):
        return super().get_queryset(request).defer("municipio__geom")


@admin.register(IncendioReportado)
class IncendioReportadoAdmin(admin.ModelAdmin):
    list_display = ("fecha", "evento", "municipio", "hectareas", "dataset")
    list_filter = ("dataset", "evento")
    search_fields = ("municipio_reportado",)
    date_hierarchy = "fecha"
    list_select_related = ("municipio",)
    raw_id_fields = ("municipio",)

    def get_queryset(self, request):
        return super().get_queryset(request).defer("municipio__geom")
