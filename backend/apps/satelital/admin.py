from django.contrib import admin

from apps.satelital.models import FocoIncendio


@admin.register(FocoIncendio)
class FocoIncendioAdmin(admin.ModelAdmin):
    list_display = ("fuente", "fecha_hora", "confianza", "brillo_frp", "satelite", "creado_en")
    list_filter = ("fuente", "satelite", "confianza")
    date_hierarchy = "fecha_hora"
    ordering = ("-fecha_hora",)
    readonly_fields = ("creado_en",)
