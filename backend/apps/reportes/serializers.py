from django.contrib.gis.geos import Point
from rest_framework import serializers

from apps.reportes.models import ReporteCiudadano

TAMANO_MAXIMO_FOTO = 5 * 1024 * 1024  # 5 MB


def _punto(p: Point) -> dict:
    return {"latitud": p.y, "longitud": p.x}


class ReporteCiudadanoSerializer(serializers.ModelSerializer):
    """
    Entrada plana (multipart desde la app móvil): `latitud_usuario`,
    `longitud_usuario` (GPS automático) y `latitud_incendio`,
    `longitud_incendio` (pin manual). Salida: ambas ubicaciones como objetos.
    """

    latitud_usuario = serializers.FloatField(write_only=True, min_value=-90, max_value=90)
    longitud_usuario = serializers.FloatField(write_only=True, min_value=-180, max_value=180)
    latitud_incendio = serializers.FloatField(write_only=True, min_value=-90, max_value=90)
    longitud_incendio = serializers.FloatField(write_only=True, min_value=-180, max_value=180)

    ubicacion_usuario = serializers.SerializerMethodField()
    ubicacion_incendio = serializers.SerializerMethodField()
    distancia_reportada_km = serializers.SerializerMethodField()
    ciudadano = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = ReporteCiudadano
        fields = [
            "id",
            "ciudadano",
            "foto",
            "descripcion",
            "latitud_usuario",
            "longitud_usuario",
            "latitud_incendio",
            "longitud_incendio",
            "ubicacion_usuario",
            "ubicacion_incendio",
            "distancia_reportada_km",
            "estado",
            "validado_por",
            "fecha_creacion",
            "fecha_validacion",
        ]
        read_only_fields = ["id", "estado", "validado_por", "fecha_creacion", "fecha_validacion"]

    def get_ubicacion_usuario(self, obj):
        return _punto(obj.ubicacion_usuario)

    def get_ubicacion_incendio(self, obj):
        return _punto(obj.ubicacion_incendio)

    def get_distancia_reportada_km(self, obj):
        return round(obj.distancia_reportada(), 3)

    def validate_foto(self, foto):
        if foto.size > TAMANO_MAXIMO_FOTO:
            raise serializers.ValidationError("La foto no puede superar 5 MB.")
        return foto

    def create(self, datos):
        usuario = Point(datos.pop("longitud_usuario"), datos.pop("latitud_usuario"), srid=4326)
        incendio = Point(datos.pop("longitud_incendio"), datos.pop("latitud_incendio"), srid=4326)
        return ReporteCiudadano.objects.create(
            ubicacion_usuario=usuario, ubicacion_incendio=incendio, **datos
        )
