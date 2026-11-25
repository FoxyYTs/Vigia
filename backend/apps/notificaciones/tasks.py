"""Tareas de Celery de notificaciones — ver Vigia-UML-Secuencia (vault de Obsidian)."""

from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from apps.alertas.models import Alerta
from apps.notificaciones.despachador import DespachadorNotificaciones, NotificadorTelegram, resumen_satelital
from apps.notificaciones.models import Notificacion


# Telegram admite unos 20 mensajes por minuto en un mismo canal; un lote de
# alertas lo superaba y respondía 429.
@shared_task(bind=True, max_retries=3, default_retry_delay=60, rate_limit="15/m")
def despachar_alerta(self, alerta_id: int) -> int:
    """Envía la alerta por sus canales; reintenta si algún envío falló.
    Retorna cuántas notificaciones quedaron enviadas en este intento."""
    alerta = Alerta.objects.select_related("foco", "municipio").defer("municipio__geom").get(pk=alerta_id)
    notificaciones = DespachadorNotificaciones().despachar(alerta)
    fallo = any(n.estado == Notificacion.Estado.FALLIDO for n in notificaciones)
    # Sin token no tiene sentido reintentar: solo llenaría la tabla de fallidos.
    if fallo and settings.TELEGRAM_BOT_TOKEN:
        try:
            raise self.retry()
        except self.MaxRetriesExceededError:
            pass
    return sum(n.estado == Notificacion.Estado.ENVIADO for n in notificaciones)


@shared_task(bind=True, max_retries=3, default_retry_delay=120)
def enviar_resumen_satelital(self) -> int:
    """Un solo mensaje, sin sonido, al canal privado con las detecciones
    satelitales que aún no se avisaron (últimas 24 h). Retorna cuántas incluyó."""
    canal = Notificacion.Canal.TELEGRAM_PRIVADO
    pendientes = list(
        Alerta.objects.filter(
            tipo_disparador=Alerta.TipoDisparador.DETECCION_SATELITAL,
            fecha_creacion__gte=timezone.now() - timedelta(hours=24),
        )
        .exclude(notificaciones__canal=canal, notificaciones__estado=Notificacion.Estado.ENVIADO)
        .select_related("foco", "municipio")
        .defer("municipio__geom")
    )
    if not pendientes:
        return 0
    ok = NotificadorTelegram().enviar_texto(
        settings.TELEGRAM_CANAL_PRIVADO_ID,
        resumen_satelital(pendientes),
        f"el resumen de {len(pendientes)} detecciones",
        silencioso=True,
    )
    if not ok and settings.TELEGRAM_BOT_TOKEN:
        try:
            raise self.retry()
        except self.MaxRetriesExceededError:
            pass
    # Una fila por alerta, como cuando salían sueltas: la pantalla del bot y la
    # selección de pendientes siguen funcionando igual. Las fallidas se vuelven
    # a intentar en el resumen siguiente.
    estado = Notificacion.Estado.ENVIADO if ok else Notificacion.Estado.FALLIDO
    ahora = timezone.now()
    previas = Notificacion.objects.filter(alerta__in=pendientes, canal=canal, usuario=None)
    previas.update(estado=estado, fecha_envio=ahora)
    con_fila = set(previas.values_list("alerta_id", flat=True))
    Notificacion.objects.bulk_create(
        [
            Notificacion(alerta=a, canal=canal, estado=estado, fecha_envio=ahora)
            for a in pendientes
            if a.pk not in con_fila
        ]
    )
    return len(pendientes) if ok else 0
