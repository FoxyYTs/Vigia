from rest_framework import serializers

from apps.historico.models import IncendioReportado


class IncendioReportadoSerializer(serializers.ModelSerializer):
    municipio = serializers.StringRelatedField()
    codigo_dane = serializers.CharField(source="municipio.codigo_dane", default=None)

    class Meta:
        model = IncendioReportado
        fields = ["id", "fecha", "evento", "hectareas", "municipio", "codigo_dane", "municipio_reportado", "dataset"]
        read_only_fields = fields
