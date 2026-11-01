from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin
from django.contrib.auth.admin import UserAdmin

from apps.usuarios.models import EntidadPublica, Municipio, Usuario


@admin.register(Usuario)
class UsuarioAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (
        ("Vigía", {"fields": ("rol", "municipio_residencia", "entidad")}),
    )
    list_display = UserAdmin.list_display + ("rol",)
    list_filter = UserAdmin.list_filter + ("rol",)


@admin.register(Municipio)
class MunicipioAdmin(GISModelAdmin):
    list_display = ("nombre", "departamento", "codigo_dane")
    search_fields = ("nombre", "departamento", "codigo_dane")


@admin.register(EntidadPublica)
class EntidadPublicaAdmin(admin.ModelAdmin):
    list_display = ("nombre",)
    filter_horizontal = ("municipios",)
