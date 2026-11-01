"""Tareas de Celery de notificaciones — ver Vigia-UML-Secuencia (vault de Obsidian)."""

from celery import shared_task
from django.conf import settings

from apps.alertas.models import Alerta
from apps.notificaciones.despachador import DespachadorNotificaciones
from apps.notificaciones.models import Notificacion


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def despachar_alerta(self, alerta_id: int) -> int:
    """Envía la alerta por sus canales; reintenta si algún envío falló.
    Retorna cuántas notificaciones quedaron enviadas en este intento."""
    alerta = Alerta.objects.select_related("foco").get(pk=alerta_id)
    notificaciones = DespachadorNotificaciones().despachar(alerta)
    fallo = any(n.estado == Notificacion.Estado.FALLIDO for n in notificaciones)
    # Sin token no tiene sentido reintentar: solo llenaría la tabla de fallidos.
    if fallo and settings.TELEGRAM_BOT_TOKEN:
        try:
            raise self.retry()
        except self.MaxRetriesExceededError:
            pass
    return sum(n.estado == Notificacion.Estado.ENVIADO for n in notificaciones)
