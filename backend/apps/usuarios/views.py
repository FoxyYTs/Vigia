import json

from django.contrib.gis.geos import MultiPolygon, Polygon
from django.core.cache import cache
from rest_framework import generics, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView

from apps.usuarios.models import Municipio
from apps.usuarios.serializers import (
    MunicipioSerializer,
    RegistroSerializer,
    TokenVigiaSerializer,
    UsuarioSerializer,
)


class RegistroView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegistroSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "registro"


class TokenView(TokenObtainPairView):
    serializer_class = TokenVigiaSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


class YoView(generics.RetrieveAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = UsuarioSerializer

    def get_object(self):
        return self.request.user


class MunicipioViewSet(viewsets.ReadOnlyModelViewSet):
    """Catálogo público (lo necesita el formulario de registro). Se
    administra desde el Django Admin, no por la API."""

    permission_classes = [AllowAny]
    serializer_class = MunicipioSerializer
    pagination_class = None  # catálogo cerrado (~1.100 municipios), la app lo carga una vez

    def get_queryset(self):
        qs = Municipio.objects.order_by("departamento", "nombre")
        departamento = self.request.query_params.get("departamento")
        return qs.filter(departamento__iexact=departamento) if departamento else qs

    @action(detail=False)
    def geometria(self, request):
        """GeoJSON de los municipios simplificado a ~1 km para dibujar capas
        por municipio en el mapa (la app lo pide una vez). En caché un día:
        los polígonos solo cambian con `cargar_municipios`."""
        geojson = cache.get(CLAVE_GEOMETRIA)
        if geojson is None:
            geojson = {"type": "FeatureCollection", "features": [
                {
                    "type": "Feature",
                    "properties": {"codigo_dane": m.codigo_dane, "nombre": m.nombre, "departamento": m.departamento},
                    "geometry": _redondear(json.loads(_simplificar(m.geom).json)),
                }
                for m in Municipio.objects.exclude(geom=None).order_by("codigo_dane")
            ]}
            cache.set(CLAVE_GEOMETRIA, geojson, 60 * 60 * 24)
        return Response(geojson)


CLAVE_GEOMETRIA = "municipios:geometria"
TOLERANCIA_MAPA = 0.01  # grados, ~1 km


def _simplificar(geom):
    """Simplifica sin cambiar de tipo: GEOS devuelve Polygon si el
    MultiPolygon tenía una sola parte, y la app espera siempre MultiPolygon."""
    simple = geom.simplify(TOLERANCIA_MAPA, preserve_topology=True)
    return MultiPolygon(simple, srid=simple.srid) if isinstance(simple, Polygon) else simple


def _redondear(geometria: dict) -> dict:
    def r(c):
        return [r(x) for x in c] if isinstance(c[0], list) else [round(c[0], 3), round(c[1], 3)]

    return {**geometria, "coordinates": r(geometria["coordinates"])}
