"""Fotos de reportes: re-codificación sin EXIF, metadatos privados, acceso con
permisos y retención (Ley 1581)."""

import io
import os
from datetime import timedelta

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from PIL import Image

from apps.reportes import fotos
from apps.reportes.models import ReporteCiudadano
from apps.reportes.tasks import purgar_fotos_reportes

pytestmark = pytest.mark.django_db


def _jpeg_con_gps(formato="JPEG", nombre="foto.jpg"):
    """Foto de 40×30 con fecha y GPS (Rionegro) en el EXIF, como la de un celular."""
    imagen = Image.new("RGB", (40, 30), "orange")
    exif = Image.Exif()
    exif[306] = "2026:10:31 14:05:00"
    exif[0x8825] = {1: "N", 2: (6.0, 9.0, 18.72), 3: "W", 4: (75.0, 22.0, 25.32)}
    buffer = io.BytesIO()
    imagen.save(buffer, format=formato, exif=exif.tobytes())
    return SimpleUploadedFile(nombre, buffer.getvalue(), content_type=f"image/{formato.lower()}")


def _datos(foto):
    return {"foto": foto, "latitud_usuario": 6.20, "longitud_usuario": -75.40,
            "latitud_incendio": 6.15, "longitud_incendio": -75.37}


def test_procesar_quita_el_exif_y_guarda_fecha_y_gps_aparte():
    limpia, miniatura, meta = fotos.procesar(_jpeg_con_gps())

    assert not Image.open(io.BytesIO(limpia.read())).getexif()  # nada de EXIF en lo que se sirve
    assert limpia.name.endswith(".jpg") and len(limpia.name) == 36  # uuid, no el nombre original
    assert meta["exif_fecha"].year == 2026 and meta["exif_fecha"].hour == 14
    assert meta["exif_ubicacion"].y == pytest.approx(6.1552, abs=1e-3)
    assert meta["exif_ubicacion"].x == pytest.approx(-75.3737, abs=1e-3)
    assert max(Image.open(io.BytesIO(miniatura.read())).size) <= fotos.LADO_MINIATURA


def test_sin_exif_los_metadatos_quedan_vacios(imagen_png):
    _, _, meta = fotos.procesar(imagen_png)
    assert meta == {"exif_fecha": None, "exif_ubicacion": None}


def test_formato_no_permitido_se_rechaza():
    gif = io.BytesIO()
    Image.new("RGB", (4, 4)).save(gif, format="GIF")
    with pytest.raises(fotos.FotoInvalida, match="JPG, PNG o WebP"):
        fotos.procesar(SimpleUploadedFile("x.gif", gif.getvalue()))


def test_crear_reporte_guarda_foto_limpia_y_metadatos_privados(api_como, ciudadano):
    r = api_como(ciudadano).post("/api/reportes/", _datos(_jpeg_con_gps()), format="multipart")
    assert r.status_code == 201
    reporte = ReporteCiudadano.objects.get(pk=r.data["id"])
    assert reporte.exif_ubicacion is not None and reporte.miniatura
    assert "exif" not in str(r.data) and "media/" not in str(r.data)
    assert r.data["foto_url"].endswith(f"/api/reportes/{reporte.pk}/foto/")


def test_la_foto_se_sirve_por_nginx_con_permisos(api_como, ciudadano, administrador, staff, crear_reporte):
    from apps.usuarios.models import Usuario

    r = api_como(ciudadano).post("/api/reportes/", _datos(_jpeg_con_gps()), format="multipart")
    url = f"/api/reportes/{r.data['id']}/foto/"
    respuesta = api_como(administrador).get(url)
    assert respuesta.status_code == 200
    assert respuesta["X-Accel-Redirect"].startswith("/protegido/media/reportes/")
    assert api_como(staff).get(url + "?miniatura=1")["X-Accel-Redirect"].endswith("_min.jpg")

    otro = Usuario.objects.create_user("otro", password="clave-segura-4", rol=Usuario.Rol.CIUDADANO)
    assert api_como(otro).get(url).status_code == 404


def test_staff_no_ve_donde_estaba_el_ciudadano(api_como, staff, administrador, ciudadano, crear_reporte):
    reporte = crear_reporte()
    url = f"/api/reportes/{reporte.pk}/"
    assert api_como(staff).get(url).data["ubicacion_usuario"] is None
    assert api_como(administrador).get(url).data["ubicacion_usuario"] is not None
    assert api_como(ciudadano).get(url).data["ubicacion_usuario"] is not None


@pytest.mark.parametrize(
    "estado,dias,se_borra",
    [("rechazado", 8, True), ("rechazado", 6, False), ("pendiente", 31, True),
     ("pendiente", 29, False), ("validado", 91, True), ("validado", 89, False)],
)
def test_retencion_por_estado(crear_reporte, estado, dias, se_borra):
    limpia, miniatura, _ = fotos.procesar(_jpeg_con_gps())
    reporte = crear_reporte(estado=estado)
    reporte.foto, reporte.miniatura = limpia, miniatura
    reporte.save()
    ruta = reporte.foto.path
    ReporteCiudadano.objects.filter(pk=reporte.pk).update(fecha_creacion=timezone.now() - timedelta(days=dias))

    assert purgar_fotos_reportes() == int(se_borra)

    reporte.refresh_from_db()
    assert bool(reporte.foto) is not se_borra and reporte.miniatura  # la miniatura siempre queda
    assert os.path.exists(ruta) is not se_borra


def test_imagen_demasiado_grande_o_de_16_bits_se_rechaza():
    grande = io.BytesIO()
    Image.new("L", (5000, 4000)).save(grande, format="PNG")
    with pytest.raises(fotos.FotoInvalida, match="demasiado grande"):
        fotos.procesar(SimpleUploadedFile("g.png", grande.getvalue()))
    profunda = io.BytesIO()
    Image.new("I;16", (10, 10)).save(profunda, format="PNG")
    with pytest.raises(fotos.FotoInvalida):
        fotos.procesar(SimpleUploadedFile("p.png", profunda.getvalue()))
