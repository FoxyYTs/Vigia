from django.contrib import admin

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente


@admin.register(CorridaModeloML)
class CorridaModeloMLAdmin(admin.ModelAdmin):
    list_display = ("version_modelo", "fecha_ejecucion")
    # Sin inline: una corrida puede tener miles de zonas.


@admin.register(ZonaRecurrente)
class ZonaRecurrenteAdmin(admin.ModelAdmin):
    list_display = ("corrida", "puntaje_recurrencia", "cantidad_incendios_historicos", "municipio")
    list_filter = ("corrida",)
    list_select_related = ("corrida", "municipio")
    raw_id_fields = ("corrida", "municipio")

    def get_queryset(self, request):
        return super().get_queryset(request).defer("municipio__geom")
