from datetime import timedelta
from html import escape

import requests
from django.conf import settings
from django.db.models import Count, Max, Q
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.notificaciones.despachador import RUTEO, DespachadorNotificaciones, NotificadorTelegram
from apps.notificaciones.models import Notificacion
from apps.notificaciones.serializers import NotificacionSerializer
from apps.usuarios.permissions import EsAdministrador, EsStaff


class NotificacionViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Bandeja del usuario: solo ve sus propias notificaciones."""

    permission_classes = [IsAuthenticated]
    serializer_class = NotificacionSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):  # al generar el esquema OpenAPI no hay usuario
            return Notificacion.objects.none()
        return Notificacion.objects.filter(usuario=self.request.user)

    @action(detail=True, methods=["post"], url_path="marcar-leida")
    def marcar_leida(self, request, pk=None):
        n = self.get_object()
        if n.estado != Notificacion.Estado.LEIDO:
            n.estado = Notificacion.Estado.LEIDO
            n.fecha_lectura = timezone.now()
            n.save(update_fields=["estado", "fecha_lectura"])
        return Response(self.get_serializer(n).data)


def _bot():
    """Nombre del bot según Telegram (getMe), o None si el token falta o no sirve."""
    if not settings.TELEGRAM_BOT_TOKEN:
        return None
    try:
        r = requests.get(f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/getMe", timeout=5)
        return r.json()["result"]["username"] if r.ok else None
    except (requests.RequestException, ValueError, KeyError):
        return None


@extend_schema(responses=OpenApiTypes.OBJECT)
@api_view(["GET"])
@permission_classes([EsAdministrador | EsStaff])
def estado_bot(request):
    """"Gestionar Bot de Telegram": si el bot responde, qué alertas recibe cada
    canal y cómo van los envíos. Nunca expone el token ni los ids de los chats."""
    desde = timezone.now() - timedelta(days=7)
    telegram = Notificacion.objects.exclude(canal=Notificacion.Canal.PUSH_APP)
    envios = {
        f["canal"]: f
        for f in telegram.values("canal").annotate(
            enviados=Count("id", filter=Q(estado=Notificacion.Estado.ENVIADO, fecha_envio__gte=desde)),
            fallidos=Count("id", filter=Q(estado=Notificacion.Estado.FALLIDO, fecha_envio__gte=desde)),
            ultimo=Max("fecha_envio", filter=Q(estado=Notificacion.Estado.ENVIADO)),
        )
    }
    canales = []
    for canal, ajuste in DespachadorNotificaciones.DESTINOS.items():
        e = envios.get(canal, {})
        canales.append({
            "canal": canal,
            "nombre": Notificacion.Canal(canal).label,
            "configurado": bool(getattr(settings, ajuste)),
            "alertas": [tipo for tipo, destinos in RUTEO.items() if canal in destinos],
            "enviados_7d": e.get("enviados", 0),
            "fallidos_7d": e.get("fallidos", 0),
            "ultimo_envio": e.get("ultimo"),
        })
    recientes = telegram.select_related("alerta__municipio").defer("alerta__municipio__geom")[:20]
    return Response({
        "bot": _bot(),
        "token_configurado": bool(settings.TELEGRAM_BOT_TOKEN),
        "canales": canales,
        "recientes": [
            {
                "fecha_envio": n.fecha_envio,
                "canal": n.canal,
                "estado": n.estado,
                "tipo_alerta": n.alerta.tipo_disparador,
                "municipio": n.alerta.municipio.nombre if n.alerta.municipio else None,
            }
            for n in recientes
        ],
    })


class _PruebaCanalSerializer(serializers.Serializer):
    canal = serializers.ChoiceField(list(DespachadorNotificaciones.DESTINOS))


@extend_schema(
    request=_PruebaCanalSerializer,
    responses={
        codigo: inline_serializer(f"ResultadoPrueba{codigo}", {"detail": serializers.CharField()})
        for codigo in (200, 502)
    },
)
@api_view(["POST"])
@permission_classes([EsStaff])
def probar_canal(request):
    """Envía un mensaje de prueba al canal `canal` para comprobar que el bot
    puede publicar ahí. No crea una Notificacion: no hay alerta detrás."""
    datos = _PruebaCanalSerializer(data=request.data)
    datos.is_valid(raise_exception=True)
    canal = datos.validated_data["canal"]
    destino = getattr(settings, DespachadorNotificaciones.DESTINOS[canal])
    # En el canal público no se muestra quién la envió: es un usuario interno.
    autor = "" if canal == Notificacion.Canal.TELEGRAM_PUBLICO else f" por {escape(request.user.username)}"
    texto = f"🧪 <b>Mensaje de prueba de Vigía</b>\nEnviado{autor} desde Gestionar Bot de Telegram."
    if not NotificadorTelegram().enviar_texto(destino, texto, f"la prueba del canal {canal}"):
        return Response(
            {"detail": "Telegram no aceptó el mensaje: revisa el token y el id del canal."},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    return Response({"detail": "Mensaje de prueba enviado."})
