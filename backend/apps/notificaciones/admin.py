from django.contrib import admin

from apps.notificaciones.models import Notificacion


@admin.register(Notificacion)
class NotificacionAdmin(admin.ModelAdmin):
    list_display = ("id", "alerta", "usuario", "canal", "estado", "fecha_envio")
    list_filter = ("canal", "estado")
