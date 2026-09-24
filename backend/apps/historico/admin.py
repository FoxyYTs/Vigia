from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from apps.historico.models import HistoricoDeforestacion


@admin.register(HistoricoDeforestacion)
class HistoricoDeforestacionAdmin(GISModelAdmin):
    list_display = ("fuente", "anio", "hectareas_afectadas", "municipio")
    list_filter = ("fuente", "anio")
