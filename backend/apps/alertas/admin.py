from django.contrib import admin

from apps.alertas.models import Alerta, AlertaReporte


# raw_id_fields: un desplegable de focos o reportes cargaría la tabla entera.
class AlertaReporteInline(admin.TabularInline):
    model = AlertaReporte
    extra = 0
    raw_id_fields = ("reporte",)
    readonly_fields = ("fecha_asociacion",)


@admin.register(Alerta)
class AlertaAdmin(admin.ModelAdmin):
    list_display = ("id", "tipo_disparador", "municipio", "fecha_creacion")
    list_filter = ("tipo_disparador",)
    date_hierarchy = "fecha_creacion"
    inlines = [AlertaReporteInline]
    raw_id_fields = ("foco", "municipio")
    list_select_related = ("municipio",)

    def get_queryset(self, request):
        # Solo se muestra el nombre del municipio, no su polígono.
        return super().get_queryset(request).defer("municipio__geom")
