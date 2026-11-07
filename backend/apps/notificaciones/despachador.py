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
from html import escape

import requests
from django.conf import settings
from django.utils import timezone

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

TITULOS = {
    Tipo.DETECCION_SATELITAL: "🛰️ Posible incendio detectado por satélite",
    Tipo.COINCIDENCIA_GEOGRAFICA: "🔥 Incendio probable: satélite y ciudadanos coinciden",
    Tipo.VALIDACION_MANUAL: "🔥 Incendio confirmado por revisión manual",
    Tipo.ACUMULACION_REPORTES: "👥 Varios ciudadanos reportan un incendio",
}
AVISOS = {
    Tipo.DETECCION_SATELITAL: "Sin confirmar en terreno.",
    Tipo.ACUMULACION_REPORTES: "Sin confirmar: pendiente de revisión.",
}
# Códigos de FIRMS y de INPE (en INPE, M-M y M-T son los pasos de mañana y tarde).
SATELITES = {
    "N": "Suomi NPP",
    "N20": "NOAA-20",
    "N21": "NOAA-21",
    "NPP-375": "Suomi NPP",
    "NPP-375D": "Suomi NPP",
    "AQUA_M-M": "Aqua",
    "AQUA_M-T": "Aqua",
    "TERRA_M-M": "Terra",
    "TERRA_M-T": "Terra",
}
# VIIRS: l, n, h. MODIS es numérico e INPE no la trae: esos casos no se muestran.
CONFIANZA = {"l": "baja", "n": "media", "h": "alta"}


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
                json={
                    "chat_id": destino,
                    "text": self.mensaje(alerta),
                    "parse_mode": "HTML",
                    # Sin esto, cada alerta trae la tarjeta genérica de OpenStreetMap.
                    "link_preview_options": {"is_disabled": True},
                },
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
        foco = alerta.foco
        lineas = [f"<b>{TITULOS[alerta.tipo_disparador]}</b>"]
        if aviso := AVISOS.get(alerta.tipo_disparador):
            lineas.append(aviso)
        lineas.append("")
        if alerta.municipio:
            lineas.append(f"📍 {escape(alerta.municipio.nombre)}, {escape(alerta.municipio.departamento)}")
        # La alerta se crea cuando llega el lote, horas después del paso del satélite.
        momento = timezone.localtime(foco.fecha_hora if foco else alerta.fecha_creacion)
        lineas.append(f"🕒 {'Detectado' if foco else 'Reportado'}: {momento:%d/%m/%Y %H:%M} (hora de Colombia)")
        if foco:
            satelite = SATELITES.get(foco.satelite, foco.satelite)
            origen = f"{escape(satelite)} ({foco.get_fuente_display()})" if satelite else foco.get_fuente_display()
            lineas.append(f"📡 Satélite: {origen}")
            if confianza := CONFIANZA.get(foco.confianza):
                lineas.append(f"📊 Confianza: {confianza}")
        if n := alerta.reportes.count():
            lineas.append(f"👥 Reportes ciudadanos: {n}")
        mapa = f"https://www.openstreetmap.org/?mlat={lat:.5f}&mlon={lon:.5f}#map=13/{lat:.5f}/{lon:.5f}"
        lineas.append(f'🗺️ <a href="{escape(mapa)}">Ver en el mapa</a> ({lat:.4f}, {lon:.4f})')
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
