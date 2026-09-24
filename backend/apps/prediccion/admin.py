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
