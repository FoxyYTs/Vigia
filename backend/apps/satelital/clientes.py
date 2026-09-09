"""
Integraciones con fuentes satelitales externas — ver Vigia-UML-Clases §
Servicios y Vigia-UML-Secuencia § Detección Satelital Automática (vault
de Obsidian).
"""

import csv
import io
import logging
from datetime import datetime, timezone

import requests
from django.conf import settings
from django.contrib.gis.geos import Point

from apps.satelital.models import FocoIncendio

logger = logging.getLogger(__name__)

# Bounding box aproximado del territorio continental colombiano
# (oeste, sur, este, norte) para el endpoint area/csv de FIRMS.
# No cubre San Andrés y Providencia (~-81.7, 12.5 — al oeste de este
# recuadro) — limitación conocida del MVP, no un descuido.
COLOMBIA_BBOX = (-79.0, -4.3, -66.8, 13.5)


class ClienteDatosExternos:
    """
    Interfaz común para los clientes de fuentes satelitales/históricas
    externas (NASA FIRMS, INPE QUEIMADAS, IDEAM, UNGRD) — ver
    Vigia-UML-Clases § Servicios. Permite agregar una quinta fuente sin
    tocar el motor de alertas.
    """

    def sincronizar(self) -> int:
        """Descarga y persiste los datos nuevos. Retorna la cantidad de
        registros nuevos creados."""
        raise NotImplementedError


def parsear_fila_firms(fila: dict, fuente: str) -> dict:
    """
    Convierte una fila del CSV de NASA FIRMS (columnas reales confirmadas
    contra la API el 09-sep-2026: latitude, longitude, acq_date, acq_time,
    confidence, frp, satellite — entre otras) en un dict normalizado.

    Función pura, sin ORM de Django ni red — se puede probar sin GDAL/GEOS
    ni base de datos. La conversión a `Point` (que sí requiere GEOS) la
    hace `ClienteNasaFirms.sincronizar()`, no esta función.

    IMPORTANTE: `confidence` en VIIRS_NOAA20_NRT es categórico
    ('l'/'n'/'h' = low/nominal/high), no un porcentaje — confirmado con
    datos reales. Se guarda tal cual llega, sin convertir a número. MODIS
    sí entrega 0-100 numérico; por eso el campo del modelo es CharField,
    no FloatField (ver FocoIncendio.confianza).
    """
    acq_time = fila["acq_time"].zfill(4)  # "58" -> "0058", "622" -> "0622"
    hora, minuto = acq_time[:2], acq_time[2:]
    fecha_hora = datetime.strptime(
        f"{fila['acq_date']} {hora}:{minuto}", "%Y-%m-%d %H:%M"
    ).replace(tzinfo=timezone.utc)

    return {
        "fuente": fuente,
        "latitud": float(fila["latitude"]),
        "longitud": float(fila["longitude"]),
        "fecha_hora": fecha_hora,
        "confianza": fila.get("confidence", ""),
        "brillo_frp": float(fila["frp"]) if fila.get("frp") else None,
        "satelite": fila.get("satellite", ""),
    }


class ClienteNasaFirms(ClienteDatosExternos):
    """
    NASA FIRMS — VIIRS_NOAA20_NRT únicamente (ver Vigia.md § Decisiones
    técnicas: Suomi NPP deja de transmitir el 1-nov-2026, no se usa esa
    fuente; decisión confirmada con José el 09-sep-2026).
    """

    FUENTE = FocoIncendio.Fuente.NASA_FIRMS
    SENSOR = "VIIRS_NOAA20_NRT"
    BASE_URL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"

    def __init__(self, map_key=None, bbox=COLOMBIA_BBOX, session=None):
        self.map_key = map_key or settings.NASA_FIRMS_MAP_KEY
        self.bbox = bbox
        self.session = session or requests.Session()

    def _url(self, dias: int) -> str:
        bbox_str = ",".join(str(v) for v in self.bbox)
        return f"{self.BASE_URL}/{self.map_key}/{self.SENSOR}/{bbox_str}/{dias}"

    def _descargar_csv(self, dias: int) -> list[dict]:
        respuesta = self.session.get(self._url(dias), timeout=30)
        respuesta.raise_for_status()
        if respuesta.text.strip() == "Invalid API call.":
            # Confirmado contra la API real: este mensaje de texto plano
            # es como FIRMS reporta un MAP_KEY o parámetro inválido — no
            # devuelve un código HTTP de error, por eso raise_for_status()
            # no lo detecta solo.
            raise ValueError(
                "NASA FIRMS rechazó la petición — revisar MAP_KEY, sensor o bbox."
            )
        return list(csv.DictReader(io.StringIO(respuesta.text)))

    def sincronizar(self, dias: int = 1) -> int:
        """
        Descarga los focos de los últimos `dias` días (1 por defecto,
        acorde a Celery Beat cada 3h) y persiste los que sean nuevos —
        ver Vigia-UML-Secuencia § Detección Satelital Automática.
        """
        filas = self._descargar_csv(dias)
        nuevos = 0
        for fila in filas:
            datos = parsear_fila_firms(fila, self.FUENTE)
            _, creado = FocoIncendio.objects.get_or_create(
                fuente=datos["fuente"],
                ubicacion=Point(datos["longitud"], datos["latitud"], srid=4326),
                fecha_hora=datos["fecha_hora"],
                defaults={
                    "confianza": datos["confianza"],
                    "brillo_frp": datos["brillo_frp"],
                    "satelite": datos["satelite"],
                },
            )
            if creado:
                nuevos += 1
        logger.info(
            "ClienteNasaFirms.sincronizar: %s focos nuevos de %s recibidos", nuevos, len(filas)
        )
        return nuevos

    def descargar_historico(self, *args, **kwargs):
        """
        NO IMPLEMENTADO A PROPÓSITO. La carga masiva del histórico de
        incendios (años de datos, no un puñado de días) no usa este
        mismo endpoint NRT — requiere el portal de descarga de archivo
        histórico de FIRMS (https://firms.modaps.eosdis.nasa.gov/download/),
        que es un flujo asíncrono (se solicita, se procesa server-side, y
        el link de descarga llega por correo), distinto de esta API REST
        síncrona. Implementar cuando se aborde la carga histórica real
        para ModeloRecurrencia — ver Vigia-Modelo-Datos § Pendiente.
        """
        raise NotImplementedError(
            "La carga histórica usa el portal de descarga de FIRMS (asíncrono, "
            "por correo), no el endpoint NRT de sincronizar(). Ver docstring."
        )
