from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from apps.historico.models import HistoricoDeforestacion, IncendioReportado


@admin.register(HistoricoDeforestacion)
class HistoricoDeforestacionAdmin(GISModelAdmin):
    list_display = ("fuente", "anio", "hectareas_afectadas", "municipio")
    list_filter = ("fuente", "anio")


@admin.register(IncendioReportado)
class IncendioReportadoAdmin(admin.ModelAdmin):
    list_display = ("fecha", "evento", "municipio", "hectareas", "dataset")
    list_filter = ("dataset", "evento")
    search_fields = ("municipio_reportado",)
    date_hierarchy = "fecha"
