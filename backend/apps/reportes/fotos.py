"""
Procesamiento de la foto de un reporte ciudadano — ver Vigia.md § Decisiones
técnicas (fotos) y la auditoría de seguridad del 1-nov-2026.

La foto se re-codifica siempre: así la imagen que se guarda y se sirve no
lleva el EXIF original (con el GPS de la casa del ciudadano) ni contenido
escondido (archivos políglotas). La fecha y el GPS del EXIF sí sirven para
detectar reportes falsos, así que se extraen antes y se guardan en campos
privados del reporte, que la API no expone.
"""

import io
import uuid
from datetime import datetime

from django.contrib.gis.geos import Point
from django.core.files.base import ContentFile
from django.utils import timezone
from PIL import Image, ImageOps, UnidentifiedImageError

FORMATOS = {"JPEG", "PNG", "WEBP"}
MAX_PIXELES = 40_000_000  # ~ 7.700 × 5.200: más que cualquier cámara de celular
LADO_FOTO = 1600
LADO_MINIATURA = 320

# Etiquetas EXIF (números estándar).
EXIF_DATETIME, EXIF_DATETIME_ORIGINAL, IFD_EXIF, IFD_GPS = 306, 36867, 0x8769, 0x8825


class FotoInvalida(ValueError):
    pass


def procesar(archivo) -> tuple[ContentFile, ContentFile, dict]:
    """(foto limpia, miniatura, metadatos privados) a partir del archivo subido."""
    try:
        imagen = Image.open(archivo)
        imagen.verify()  # detecta archivos truncados o corruptos
        archivo.seek(0)
        imagen = Image.open(archivo)
    except (UnidentifiedImageError, OSError) as e:
        raise FotoInvalida("El archivo no es una imagen válida.") from e
    if imagen.format not in FORMATOS:
        raise FotoInvalida("La foto debe ser JPG, PNG o WebP.")
    if imagen.width * imagen.height > MAX_PIXELES:
        raise FotoInvalida("La foto tiene demasiados píxeles.")

    metadatos = _metadatos(imagen)
    limpia = ImageOps.exif_transpose(imagen).convert("RGB")  # respeta la orientación sin copiar el EXIF
    nombre = uuid.uuid4().hex
    return (
        _jpeg(limpia, LADO_FOTO, 85, f"{nombre}.jpg"),
        _jpeg(limpia, LADO_MINIATURA, 75, f"{nombre}_min.jpg"),
        metadatos,
    )


def _jpeg(imagen: Image.Image, lado: int, calidad: int, nombre: str) -> ContentFile:
    copia = imagen.copy()
    copia.thumbnail((lado, lado))
    buffer = io.BytesIO()
    copia.save(buffer, format="JPEG", quality=calidad, optimize=True)  # sin exif=…: sale limpia
    return ContentFile(buffer.getvalue(), name=nombre)


def _metadatos(imagen: Image.Image) -> dict:
    exif = imagen.getexif()
    fecha = exif.get_ifd(IFD_EXIF).get(EXIF_DATETIME_ORIGINAL) or exif.get(EXIF_DATETIME)
    return {"exif_fecha": _fecha(fecha), "exif_ubicacion": _gps(exif.get_ifd(IFD_GPS))}


def _fecha(texto) -> datetime | None:
    try:
        # El EXIF trae la hora local del celular, sin zona: se asume la de Colombia.
        return timezone.make_aware(datetime.strptime(str(texto).strip("\x00 "), "%Y:%m:%d %H:%M:%S"))
    except (TypeError, ValueError):
        return None


def _gps(gps: dict) -> Point | None:
    try:
        lat = _grados(gps[2]) * (-1 if gps.get(1) == "S" else 1)
        lon = _grados(gps[4]) * (-1 if gps.get(3) == "W" else 1)
    except (KeyError, TypeError, ValueError, ZeroDivisionError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return Point(lon, lat, srid=4326)


def _grados(gms) -> float:
    g, m, s = (float(v) for v in gms)
    return g + m / 60 + s / 3600
