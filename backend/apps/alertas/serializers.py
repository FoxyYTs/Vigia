from rest_framework import serializers

from apps.alertas.models import Alerta


class AlertaSerializer(serializers.ModelSerializer):
    latitud = serializers.FloatField(source="ubicacion.y", read_only=True)
    longitud = serializers.FloatField(source="ubicacion.x", read_only=True)
    municipio = serializers.StringRelatedField()

    class Meta:
        model = Alerta
        fields = ["id", "tipo_disparador", "foco", "latitud", "longitud", "municipio", "fecha_creacion"]
        read_only_fields = fields
