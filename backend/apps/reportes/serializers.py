from django.contrib.gis.geos import Point
from django.urls import reverse
from rest_framework import serializers

from apps.reportes import fotos
from apps.reportes.models import ReporteCiudadano
from apps.satelital.geografia import esta_en_colombia

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

    foto = serializers.ImageField(write_only=True)
    foto_url = serializers.SerializerMethodField(help_text="Solo con sesión y permiso sobre el reporte.")
    miniatura_url = serializers.SerializerMethodField()
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
            "foto_url",
            "miniatura_url",
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

    def _url_foto(self, obj, miniatura=False):
        if not (obj.miniatura if miniatura else obj.foto):
            return None  # la foto ya se borró por retención
        url = reverse("reporte-foto", args=[obj.pk]) + ("?miniatura=1" if miniatura else "")
        request = self.context.get("request")
        return request.build_absolute_uri(url) if request else url

    def get_foto_url(self, obj):
        return self._url_foto(obj)

    def get_miniatura_url(self, obj):
        return self._url_foto(obj, miniatura=True)

    def get_ubicacion_usuario(self, obj):
        # Dónde estaba el ciudadano es dato personal: solo lo ven él y los
        # administradores (que ya están limitados a su jurisdicción), no Staff.
        usuario = getattr(self.context.get("request"), "user", None)
        if usuario is None or not (usuario.es_administrador() or usuario.pk == obj.ciudadano_id):
            return None
        return _punto(obj.ubicacion_usuario)

    def get_ubicacion_incendio(self, obj):
        return _punto(obj.ubicacion_incendio)

    def get_distancia_reportada_km(self, obj):
        return round(obj.distancia_reportada(), 3)

    descripcion = serializers.CharField(required=False, allow_blank=True, max_length=2000)

    def validate(self, datos):
        # Un reporte fuera de Colombia no le sirve a ninguna entidad y permitiría
        # disparar alertas en cualquier parte del mundo.
        if not esta_en_colombia(datos["longitud_incendio"], datos["latitud_incendio"]):
            raise serializers.ValidationError({"latitud_incendio": "El incendio debe estar en Colombia."})
        return datos

    def validate_foto(self, foto):
        if foto.size > TAMANO_MAXIMO_FOTO:
            raise serializers.ValidationError("La foto no puede superar 5 MB.")
        try:
            return fotos.procesar(foto)
        except fotos.FotoInvalida as e:
            raise serializers.ValidationError(str(e)) from None

    def create(self, datos):
        usuario = Point(datos.pop("longitud_usuario"), datos.pop("latitud_usuario"), srid=4326)
        incendio = Point(datos.pop("longitud_incendio"), datos.pop("latitud_incendio"), srid=4326)
        foto, miniatura, metadatos = datos.pop("foto")
        return ReporteCiudadano.objects.create(
            ubicacion_usuario=usuario, ubicacion_incendio=incendio, foto=foto, miniatura=miniatura,
            **metadatos, **datos,
        )
