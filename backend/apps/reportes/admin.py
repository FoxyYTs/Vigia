from django.contrib import admin

from apps.reportes.models import ReporteCiudadano


@admin.register(ReporteCiudadano)
class ReporteCiudadanoAdmin(admin.ModelAdmin):
    list_display = ("id", "ciudadano", "estado", "fecha_creacion", "validado_por")
    list_filter = ("estado",)
    date_hierarchy = "fecha_creacion"
    readonly_fields = ("fecha_creacion",)
