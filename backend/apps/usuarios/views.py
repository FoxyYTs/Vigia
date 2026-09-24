from rest_framework import generics, viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
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
