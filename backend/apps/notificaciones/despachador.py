"""
DespachadorNotificaciones y Notificador — ver Vigia-UML-Clases § Servicios
(vault de Obsidian). Por ahora solo Telegram: el push (FCM) llega con la app
móvil, cuando existan tokens de dispositivo a los que enviar.

Ruteo por certeza (decisión de José, 31-oct-2026):
- público  ← alertas confirmadas (coincidencia geográfica, validación manual)
- privado  ← todas (entidades públicas)
- interno  ← acumulación de reportes (admins, para que los validen)
"""

import logging

import requests
from django.conf import settings

from apps.alertas.models import Alerta
from apps.notificaciones.models import Notificacion

logger = logging.getLogger(__name__)

Tipo, Canal = Alerta.TipoDisparador, Notificacion.Canal

RUTEO = {
    Tipo.DETECCION_SATELITAL: [Canal.TELEGRAM_PRIVADO],
    Tipo.COINCIDENCIA_GEOGRAFICA: [Canal.TELEGRAM_PUBLICO, Canal.TELEGRAM_PRIVADO],
    Tipo.VALIDACION_MANUAL: [Canal.TELEGRAM_PUBLICO, Canal.TELEGRAM_PRIVADO],
    Tipo.ACUMULACION_REPORTES: [Canal.TELEGRAM_PRIVADO, Canal.TELEGRAM_INTERNO],
}


class Notificador:
    def enviar(self, alerta: Alerta, destino: str) -> bool:
        raise NotImplementedError


class NotificadorTelegram(Notificador):
    URL = "https://api.telegram.org/bot{token}/sendMessage"

    def enviar(self, alerta: Alerta, destino: str) -> bool:
        token = settings.TELEGRAM_BOT_TOKEN
        if not token or not destino:
            logger.warning("Telegram sin configurar: alerta %s no enviada", alerta.pk)
            return False
        try:
            r = requests.post(
                self.URL.format(token=token),
                json={"chat_id": destino, "text": self.mensaje(alerta)},
                timeout=10,
            )
        except requests.RequestException:
            # Sin el token en el log: va dentro de la URL.
            logger.error("Telegram no respondió para la alerta %s", alerta.pk)
            return False
        if not r.ok:
            logger.error("Telegram rechazó la alerta %s: %s", alerta.pk, r.text[:200])
        return r.ok

    @staticmethod
    def mensaje(alerta: Alerta) -> str:
        lon, lat = alerta.ubicacion.x, alerta.ubicacion.y
        lineas = [
            f"🔥 Vigía — {alerta.get_tipo_disparador_display()}",
            f"Fecha: {alerta.fecha_creacion:%Y-%m-%d %H:%M} UTC",
            f"Ubicación: {lat:.4f}, {lon:.4f}",
        ]
        if alerta.foco:
            lineas.append(f"Fuente: {alerta.foco.get_fuente_display()} {alerta.foco.satelite}".rstrip())
        if n := alerta.reportes.count():
            lineas.append(f"Reportes ciudadanos: {n}")
        lineas.append(f"Mapa: https://www.openstreetmap.org/?mlat={lat:.5f}&mlon={lon:.5f}#map=13/{lat:.5f}/{lon:.5f}")
        return "\n".join(lineas)


class DespachadorNotificaciones:
    DESTINOS = {
        Canal.TELEGRAM_PUBLICO: "TELEGRAM_CANAL_PUBLICO_ID",
        Canal.TELEGRAM_PRIVADO: "TELEGRAM_CANAL_PRIVADO_ID",
        Canal.TELEGRAM_INTERNO: "TELEGRAM_CANAL_INTERNO_ID",
    }

    def __init__(self, notificador: Notificador | None = None):
        self.notificador = notificador or NotificadorTelegram()

    def despachar(self, alerta: Alerta) -> list[Notificacion]:
        """Una `Notificacion` por canal. Ya enviados no se repiten, para
        que un reintento de la tarea no duplique mensajes."""
        notificaciones = []
        for canal in RUTEO[alerta.tipo_disparador]:
            if alerta.notificaciones.filter(canal=canal, estado=Notificacion.Estado.ENVIADO).exists():
                continue
            ok = self.notificador.enviar(alerta, getattr(settings, self.DESTINOS[canal]))
            notificaciones.append(
                Notificacion.objects.create(
                    alerta=alerta,
                    canal=canal,
                    estado=Notificacion.Estado.ENVIADO if ok else Notificacion.Estado.FALLIDO,
                )
            )
        return notificaciones
