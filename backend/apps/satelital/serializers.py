from rest_framework import serializers

from apps.satelital.models import FocoIncendio


class FocoIncendioSerializer(serializers.ModelSerializer):
    latitud = serializers.FloatField(source="ubicacion.y", read_only=True)
    longitud = serializers.FloatField(source="ubicacion.x", read_only=True)

    class Meta:
        model = FocoIncendio
        fields = ["id", "fuente", "latitud", "longitud", "fecha_hora", "confianza", "brillo_frp", "satelite"]
        read_only_fields = fields
