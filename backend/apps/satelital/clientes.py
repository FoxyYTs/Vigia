"""
Integraciones con fuentes satelitales externas — ver Vigia-UML-Clases §
Servicios y Vigia-UML-Secuencia § Detección Satelital Automática (vault
de Obsidian).
"""

import csv
import io
import logging
import time
from datetime import date, datetime, timedelta, timezone

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


# La API area/csv de FIRMS acepta como máximo 5 días por consulta.
VENTANA_MAX_DIAS_FIRMS = 5


def ventanas_de_dias(desde: date, hasta: date, tamano: int = VENTANA_MAX_DIAS_FIRMS):
    """
    Parte el rango [desde, hasta] (ambos inclusive) en ventanas consecutivas
    de a lo sumo `tamano` días. Devuelve tuplas (fecha_inicio, dias) — el
    formato que espera el endpoint area/csv de FIRMS (DAY_RANGE + DATE).
    """
    if hasta < desde:
        raise ValueError("`hasta` no puede ser anterior a `desde`.")
    actual = desde
    while actual <= hasta:
        dias = min(tamano, (hasta - actual).days + 1)
        yield actual, dias
        actual += timedelta(days=dias)


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

    def _contar(self) -> int:
        return FocoIncendio.objects.filter(fuente=self.FUENTE).count()

    def _insertar_masivo(self, datos: list[dict], lote: int = 5000) -> None:
        """
        Inserción en lote que descarta silenciosamente los duplicados (la
        UniqueConstraint fuente+ubicacion+fecha_hora de FocoIncendio) — a
        diferencia de get_or_create fila por fila, aguanta millones de
        registros del histórico. No informa cuántos fueron nuevos: quien
        llama compara `_contar()` antes y después.
        """
        FocoIncendio.objects.bulk_create(
            [
                FocoIncendio(
                    fuente=d["fuente"],
                    ubicacion=Point(d["longitud"], d["latitud"], srid=4326),
                    fecha_hora=d["fecha_hora"],
                    confianza=d["confianza"],
                    brillo_frp=d["brillo_frp"],
                    satelite=d["satelite"],
                )
                for d in datos
            ],
            batch_size=lote,
            ignore_conflicts=True,
        )


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
    SENSOR_HISTORICO = "VIIRS_NOAA20_SP"
    BASE_URL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"

    def __init__(self, map_key=None, bbox=COLOMBIA_BBOX, session=None):
        self.map_key = map_key or settings.NASA_FIRMS_MAP_KEY
        self.bbox = bbox
        self.session = session or requests.Session()

    def _url(self, dias: int, fecha: date | None = None, sensor: str | None = None) -> str:
        bbox_str = ",".join(str(v) for v in self.bbox)
        url = f"{self.BASE_URL}/{self.map_key}/{sensor or self.SENSOR}/{bbox_str}/{dias}"
        return f"{url}/{fecha.isoformat()}" if fecha else url

    def _descargar_csv(
        self, dias: int, fecha: date | None = None, sensor: str | None = None
    ) -> list[dict]:
        respuesta = self.session.get(self._url(dias, fecha, sensor), timeout=60)
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

    def descargar_historico(
        self,
        desde: date,
        hasta: date,
        sensor: str | None = None,
        pausa: float = 0.2,
    ) -> int:
        """
        Carga masiva de focos entre `desde` y `hasta` (inclusive) usando el
        mismo endpoint area/csv con el parámetro DATE, en ventanas de 5 días.

        CORRECCIÓN 23-sep-2026 (probado contra la API real): una versión
        anterior de este método decía que el histórico solo se podía pedir
        por el portal de descarga asíncrono (enlace por correo). No es
        cierto: la MAP_KEY sirve para el archivo histórico con las fuentes
        "Standard Processing" (`*_SP`). Cobertura confirmada con
        data_availability el 23-sep-2026:

          VIIRS_NOAA20_SP  2018-04-01 → 2026-06-30
          VIIRS_NOAA20_NRT 2026-07-01 → hoy  (empalma sin hueco con el SP)
          VIIRS_SNPP_SP    2012-01-20 → 2026-06-30
          MODIS_SP         2000-11-01 → 2026-06-30

        `sensor` por defecto es VIIRS_NOAA20_SP, el mismo instrumento que
        usa la sincronización en tiempo real: una serie de un solo sensor
        evita que la llegada de satélites nuevos parezca un aumento de
        incendios en el modelo de recurrencia.

        Retorna la cantidad de focos nuevos insertados.
        """
        sensor = sensor or self.SENSOR_HISTORICO
        antes = self._contar()
        for inicio, dias in ventanas_de_dias(desde, hasta):
            filas = self._descargar_csv(dias, inicio, sensor)
            self._insertar_masivo([parsear_fila_firms(f, self.FUENTE) for f in filas])
            logger.info(
                "ClienteNasaFirms.descargar_historico: %s + %s días → %s filas (%s)",
                inicio, dias, len(filas), sensor,
            )
            time.sleep(pausa)  # 5000 transacciones/10 min por MAP_KEY
        return self._contar() - antes


def parsear_feature_inpe(feature: dict, fuente: str = FocoIncendio.Fuente.INPE_QUEIMADAS) -> dict:
    """
    Convierte un Feature GeoJSON del WFS de INPE (capa bdqueimadas2:focos,
    propiedades confirmadas contra el servicio real el 23-sep-2026) en el
    mismo dict normalizado que `parsear_fila_firms`. Función pura.

    INPE no entrega un nivel de confianza, así que `confianza` queda vacío.
    `data_hora_gmt` viene como "2026-09-23T20:10:00Z".
    """
    props = feature["properties"]
    fecha_hora = datetime.strptime(props["data_hora_gmt"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    return {
        "fuente": fuente,
        "latitud": float(props["latitude"]),
        "longitud": float(props["longitude"]),
        "fecha_hora": fecha_hora,
        "confianza": "",
        "brillo_frp": float(props["frp"]) if props.get("frp") is not None else None,
        "satelite": props.get("satelite") or "",
    }


class ClienteInpeQueimadas(ClienteDatosExternos):
    """
    INPE QUEIMADAS vía WFS público (sin credenciales) — ver
    Vigia-Credenciales-APIs § INPE QUEIMADAS.

    Se usa la capa `bdqueimadas2:focos` filtrada por `pais='Colombia'`. Las
    capas `dados_abertos:*_br_*` que la nota de credenciales listaba solo
    cubren Brasil (verificado el 23-sep-2026: sus puntos caen en territorio
    brasileño aunque el bbox toque Colombia).

    Qué aporta frente a FIRMS: entrega detecciones de todos los satélites que
    INPE procesa, entre ellos GOES-19 (geoestacionario, cada 10 min), que
    FIRMS no tiene. Las detecciones VIIRS (NPP-375, NOAA-20, NOAA-21) son en
    buena parte las mismas que FIRMS con otro identificador: se guardan con
    `fuente=INPE_QUEIMADAS` y su `satelite`, y el motor de alertas no
    necesita deduplicarlas (usa un radio de 10 km). Para entrenar el modelo
    de recurrencia usar solo `fuente=NASA_FIRMS`.
    """

    FUENTE = FocoIncendio.Fuente.INPE_QUEIMADAS
    CAPA = "bdqueimadas2:focos"
    PAIS = "Colombia"
    TAMANO_PAGINA = 5000

    def __init__(self, url=None, session=None):
        self.url = url or settings.INPE_QUEIMADAS_WFS_URL
        self.session = session or requests.Session()

    def _params(self, desde: datetime, inicio: int) -> dict:
        return {
            "service": "WFS",
            "version": "2.0.0",
            "request": "GetFeature",
            "typeNames": self.CAPA,
            "outputFormat": "application/json",
            "cql_filter": (
                f"pais='{self.PAIS}' AND data_hora_gmt >= {desde:%Y-%m-%dT%H:%M:%SZ}"
            ),
            # Orden estable: sin él la paginación por startIndex no es confiable.
            "sortBy": "id_foco_bdq",
            "count": self.TAMANO_PAGINA,
            "startIndex": inicio,
        }

    def _descargar(self, desde: datetime) -> list[dict]:
        features: list[dict] = []
        inicio = 0
        while True:
            respuesta = self.session.get(self.url, params=self._params(desde, inicio), timeout=120)
            respuesta.raise_for_status()
            pagina = respuesta.json()["features"]
            features.extend(pagina)
            if len(pagina) < self.TAMANO_PAGINA:
                return features
            inicio += self.TAMANO_PAGINA

    def sincronizar(self, dias: int = 1) -> int:
        """Descarga los focos de Colombia de los últimos `dias` días y
        persiste los nuevos. Retorna la cantidad de focos nuevos."""
        desde = datetime.now(timezone.utc) - timedelta(days=dias)
        features = self._descargar(desde)
        antes = self._contar()
        self._insertar_masivo([parsear_feature_inpe(f) for f in features])
        nuevos = self._contar() - antes
        logger.info(
            "ClienteInpeQueimadas.sincronizar: %s focos nuevos de %s recibidos",
            nuevos, len(features),
        )
        return nuevos
