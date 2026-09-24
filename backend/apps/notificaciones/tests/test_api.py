import pytest

from apps.alertas.models import Alerta
from apps.notificaciones.models import Notificacion
from apps.usuarios.models import Usuario

pytestmark = pytest.mark.django_db


@pytest.fixture
def alerta(foco):
    return Alerta.objects.create(tipo_disparador="deteccion_satelital", foco=foco, ubicacion=foco.ubicacion)


def _notif(alerta, usuario):
    return Notificacion.objects.create(alerta=alerta, usuario=usuario, canal=Notificacion.Canal.PUSH_APP)


def test_exige_sesion(api):
    assert api.get("/api/notificaciones/").status_code == 401


def test_cada_usuario_ve_solo_las_suyas(api_como, alerta, ciudadano, administrador):
    mia, ajena = _notif(alerta, ciudadano), _notif(alerta, administrador)
    Notificacion.objects.create(alerta=alerta, canal=Notificacion.Canal.TELEGRAM_PUBLICO)  # sin usuario
    cliente = api_como(ciudadano)
    assert {n["id"] for n in cliente.get("/api/notificaciones/").data["results"]} == {mia.id}
    assert cliente.get(f"/api/notificaciones/{ajena.id}/").status_code == 404


def test_marcar_como_leida(api_como, alerta, ciudadano):
    n = _notif(alerta, ciudadano)
    r = api_como(ciudadano).post(f"/api/notificaciones/{n.id}/marcar-leida/")
    assert r.status_code == 200 and r.data["estado"] == "leido" and r.data["fecha_lectura"]


def test_marcar_leida_es_idempotente(api_como, alerta, ciudadano):
    n = _notif(alerta, ciudadano)
    cliente = api_como(ciudadano)
    primera = cliente.post(f"/api/notificaciones/{n.id}/marcar-leida/").data["fecha_lectura"]
    assert cliente.post(f"/api/notificaciones/{n.id}/marcar-leida/").data["fecha_lectura"] == primera


def test_no_se_marca_la_de_otro_usuario(api_como, alerta, ciudadano, administrador):
    ajena = _notif(alerta, administrador)
    assert api_como(ciudadano).post(f"/api/notificaciones/{ajena.id}/marcar-leida/").status_code == 404
    ajena.refresh_from_db()
    assert ajena.estado == "enviado"
