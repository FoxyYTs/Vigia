from rest_framework import serializers

from apps.notificaciones.models import Notificacion


class NotificacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notificacion
        fields = ["id", "alerta", "canal", "estado", "fecha_envio", "fecha_lectura"]
        read_only_fields = fields
