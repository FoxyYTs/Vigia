from django.contrib import admin

from apps.alertas.models import Alerta, AlertaReporte


class AlertaReporteInline(admin.TabularInline):
    model = AlertaReporte
    extra = 0
    readonly_fields = ("fecha_asociacion",)


@admin.register(Alerta)
class AlertaAdmin(admin.ModelAdmin):
    list_display = ("id", "tipo_disparador", "municipio", "fecha_creacion")
    list_filter = ("tipo_disparador",)
    date_hierarchy = "fecha_creacion"
    inlines = [AlertaReporteInline]
