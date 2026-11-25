import json

from django.contrib.gis.geos import MultiPolygon, Polygon
from django.core.cache import cache
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Q
from django.contrib.auth.password_validation import validate_password
from rest_framework import generics, mixins, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from django.utils.decorators import method_decorator
from django.views.decorators.cache import never_cache
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.views import TokenBlacklistView, TokenObtainPairView, TokenRefreshView

from apps.usuarios.models import EntidadPublica, Municipio, Usuario
from apps.usuarios.permissions import EsAdministrador, EsStaff
from apps.usuarios.recuperacion import usar_codigo, generar_codigo
from apps.usuarios.tasks import enviar_codigo_recuperacion
from apps.usuarios.serializers import (
    EntidadSerializer,
    GestionUsuarioSerializer,
    MunicipioSerializer,
    RecuperarConfirmacionSerializer,
    RecuperarSolicitudSerializer,
    RegistroSerializer,
    TokenVigiaSerializer,
    UsuarioSerializer,
)


class RegistroView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegistroSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "registro"


def _cuenta_por_correo(email):
    # shortcut: si dos cuentas comparten correo (creadas en el admin), se usa la
    # más antigua; el registro ya no deja repetirlo.
    return Usuario.objects.filter(email__iexact=email, is_active=True).order_by("pk").first()


@method_decorator(never_cache, name="dispatch")
class RecuperarSolicitudView(generics.GenericAPIView):
    """Envía un código de 6 dígitos al correo de la cuenta. Responde igual exista
    o no, para no revelar qué correos están registrados."""

    permission_classes = [AllowAny]
    serializer_class = RecuperarSolicitudSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "recuperar"

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if usuario := _cuenta_por_correo(serializer.validated_data["email"]):
            enviar_codigo_recuperacion.delay(usuario.email, usuario.username, generar_codigo(usuario))
        return Response({"detail": "Si el correo está registrado, te llegará un código de 6 dígitos."})


@method_decorator(never_cache, name="dispatch")
class RecuperarConfirmacionView(generics.GenericAPIView):
    """Cambia la contraseña con el código recibido y cierra todas las sesiones."""

    permission_classes = [AllowAny]
    serializer_class = RecuperarConfirmacionSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "recuperar-confirmar"

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        datos = serializer.validated_data
        usuario = _cuenta_por_correo(datos["email"])
        # La contraseña se valida antes de gastar el código (y también sin
        # cuenta, para que la respuesta no revele si el correo existe).
        try:
            validate_password(datos["password"], usuario or Usuario(email=datos["email"]))
        except DjangoValidationError as e:
            raise serializers.ValidationError({"password": list(e.messages)}) from None
        if usuario is None or not usar_codigo(usuario, datos["codigo"]):
            raise serializers.ValidationError({"codigo": ["El código no es válido o ya venció. Pide uno nuevo."]})
        usuario.set_password(datos["password"])
        usuario.save(update_fields=["password"])
        _revocar_sesiones(usuario)
        return Response({"detail": "Listo: ya puedes iniciar sesión con tu nueva contraseña."})


@method_decorator(never_cache, name="dispatch")
class TokenView(TokenObtainPairView):
    serializer_class = TokenVigiaSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


@method_decorator(never_cache, name="dispatch")
class RefrescoView(TokenRefreshView):
    """Con ROTATE_REFRESH_TOKENS devuelve también un refresh nuevo."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "refresco"

    def post(self, request, *args, **kwargs):
        # simplejwt busca al usuario del refresh y no captura DoesNotExist: el
        # refresh de una cuenta borrada en el admin respondía 500 en vez de 401.
        try:
            return super().post(request, *args, **kwargs)
        except Usuario.DoesNotExist:
            raise InvalidToken("La cuenta de esta sesión ya no existe.") from None


@method_decorator(never_cache, name="dispatch")
class CerrarSesionView(TokenBlacklistView):
    """Revoca el refresh: después de cerrar sesión ya no sirve aunque alguien
    lo haya copiado."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "refresco"


class YoView(generics.RetrieveDestroyAPIView):
    """GET: perfil. DELETE: elimina la cuenta (anonimiza los datos personales
    y revoca las sesiones abiertas)."""

    permission_classes = [IsAuthenticated]
    serializer_class = UsuarioSerializer

    def get_object(self):
        return self.request.user

    def perform_destroy(self, usuario):
        _revocar_sesiones(usuario)
        usuario.anonimizar()


def _revocar_sesiones(usuario):
    BlacklistedToken.objects.bulk_create(
        [BlacklistedToken(token=t) for t in OutstandingToken.objects.filter(user=usuario)], ignore_conflicts=True
    )


class GestionUsuarioViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """"Gestionar Permisos". El staff ve a todos y cambia rol, entidad y si la
    cuenta está activa (PATCH). El administrador solo consulta a los
    administradores de su entidad: no ve ciudadanos ni sus correos.
    Filtros: `buscar` (usuario o correo) y `rol`."""

    permission_classes = [EsAdministrador | EsStaff]
    serializer_class = GestionUsuarioSerializer
    http_method_names = ["get", "patch"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):  # al generar el esquema OpenAPI no hay usuario
            return Usuario.objects.none()
        usuario = self.request.user
        qs = Usuario.objects.select_related("entidad").order_by("username")
        if not usuario.es_staff():
            # Él mismo y, si tiene entidad, los demás administradores de ella.
            qs = qs.filter(
                Q(pk=usuario.pk)
                | Q(rol=Usuario.Rol.ADMINISTRADOR, entidad=usuario.entidad_id, entidad__isnull=False)
            )
        params = self.request.query_params
        if buscar := params.get("buscar", "").strip():
            qs = qs.filter(Q(username__icontains=buscar) | Q(email__icontains=buscar))
        if rol := params.get("rol"):
            qs = qs.filter(rol=rol)
        return qs

    def update(self, request, *args, **kwargs):
        if not request.user.es_staff():
            raise PermissionDenied("Solo el staff cambia roles y permisos.")
        objetivo = self.get_object()
        # Sin autoedición (nadie se quita el rol por error) ni superusuarios,
        # que se gestionan en el Django Admin.
        if objetivo == request.user or objetivo.is_superuser:
            raise PermissionDenied("Esta cuenta no se puede modificar desde aquí.")
        return super().update(request, *args, **kwargs)

    def perform_update(self, serializer):
        rol_antes, activo_antes = serializer.instance.rol, serializer.instance.is_active
        rol = serializer.validated_data.get("rol", rol_antes)
        # El acceso al Django Admin va con el rol: un staff degradado no debe conservarlo.
        usuario = serializer.save(is_staff=rol == Usuario.Rol.STAFF)
        # El rol viaja en el JWT y se copia en cada renovación: si cambia, o si
        # la cuenta se desactiva, se cierran las sesiones para que vuelva a
        # entrar con el rol nuevo (o no pueda entrar).
        if usuario.rol != rol_antes or (activo_antes and not usuario.is_active):
            _revocar_sesiones(usuario)


class EntidadViewSet(viewsets.ReadOnlyModelViewSet):
    """Entidades públicas, para asignarlas a los administradores."""

    permission_classes = [EsAdministrador | EsStaff]
    serializer_class = EntidadSerializer
    queryset = EntidadPublica.objects.order_by("nombre")
    pagination_class = None



class MunicipioViewSet(viewsets.ReadOnlyModelViewSet):
    """Catálogo público (lo necesita el formulario de registro). Se
    administra desde el Django Admin, no por la API."""

    permission_classes = [AllowAny]
    serializer_class = MunicipioSerializer
    pagination_class = None  # catálogo cerrado (~1.100 municipios), la app lo carga una vez

    def get_queryset(self):
        # Sin el polígono: el formulario de registro solo necesita los nombres.
        qs = Municipio.objects.only("id", "nombre", "departamento", "codigo_dane").order_by("departamento", "nombre")
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
