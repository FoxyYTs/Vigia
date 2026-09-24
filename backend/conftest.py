"""Fixtures compartidas — requieren PostGIS (correr dentro de Docker)."""

from datetime import datetime, timezone

import io

import pytest
from django.contrib.gis.geos import Point
from django.core.cache import cache
from PIL import Image
from rest_framework.test import APIClient

from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import EntidadPublica, Municipio, Usuario

RIONEGRO = Point(-75.3737, 6.1552, srid=4326)  # (lon, lat)


@pytest.fixture
def municipio(db):
    return Municipio.objects.create(nombre="Rionegro", departamento="Antioquia")


@pytest.fixture
def entidad(db, municipio):
    e = EntidadPublica.objects.create(nombre="Cornare")
    e.municipios.add(municipio)
    return e


@pytest.fixture
def ciudadano(db, municipio):
    return Usuario.objects.create_user(
        "ciudadano1", password="clave-segura-1", rol=Usuario.Rol.CIUDADANO, municipio_residencia=municipio
    )


@pytest.fixture
def administrador(db, entidad):
    return Usuario.objects.create_user(
        "admin1", password="clave-segura-2", rol=Usuario.Rol.ADMINISTRADOR, entidad=entidad
    )


@pytest.fixture
def staff(db):
    return Usuario.objects.create_user(
        "staff1", password="clave-segura-3", rol=Usuario.Rol.STAFF, is_staff=True
    )


@pytest.fixture
def foco(db):
    return FocoIncendio.objects.create(
        fuente=FocoIncendio.Fuente.NASA_FIRMS,
        ubicacion=RIONEGRO,
        fecha_hora=datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc),
        confianza="n",
    )


@pytest.fixture
def crear_reporte(db, ciudadano):
    """Fábrica: crea un reporte con ubicaciones (lon, lat) configurables."""

    def _crear(incendio=RIONEGRO, usuario=RIONEGRO, **extra):
        return ReporteCiudadano.objects.create(
            ciudadano=extra.pop("ciudadano", ciudadano),
            foto="reportes/prueba.jpg",
            ubicacion_usuario=usuario,
            ubicacion_incendio=incendio,
            **extra,
        )

    return _crear


@pytest.fixture
def reporte(crear_reporte):
    return crear_reporte()


@pytest.fixture(autouse=True)
def _aislar_efectos_laterales(settings, tmp_path):
    """Cada test arranca sin contadores de throttling y escribe las fotos
    subidas en un directorio temporal, no en backend/media."""
    cache.clear()
    settings.MEDIA_ROOT = tmp_path / "media"


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def api_como(api):
    """api_como(usuario) → cliente autenticado como ese usuario."""

    def _como(usuario):
        api.force_authenticate(usuario)
        return api

    return _como


@pytest.fixture
def imagen_png():
    """Foto mínima pero válida (Pillow la abre) para los endpoints con ImageField."""
    from django.core.files.uploadedfile import SimpleUploadedFile

    buffer = io.BytesIO()
    Image.new("RGB", (4, 4), "orange").save(buffer, format="PNG")
    return SimpleUploadedFile("foco.png", buffer.getvalue(), content_type="image/png")
