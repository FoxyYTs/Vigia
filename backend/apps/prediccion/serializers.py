import json

from rest_framework import serializers

from apps.prediccion.models import ZonaRecurrente


class ZonaRecurrenteSerializer(serializers.ModelSerializer):
    area = serializers.SerializerMethodField(help_text="Geometría GeoJSON (MultiPolygon).")
    municipio = serializers.StringRelatedField()

    class Meta:
        model = ZonaRecurrente
        fields = ["id", "corrida", "area", "puntaje_recurrencia", "cantidad_incendios_historicos", "municipio"]
        read_only_fields = fields

    def get_area(self, obj):
        return json.loads(obj.area.geojson)
