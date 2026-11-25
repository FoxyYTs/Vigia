from unittest import mock

import pytest
from django.core import mail
from rest_framework_simplejwt.tokens import RefreshToken

from apps.usuarios import recuperacion
from apps.usuarios.tasks import enviar_codigo_recuperacion

pytestmark = pytest.mark.django_db

NUEVA = "otra-clave-larga-654"


@pytest.fixture(autouse=True)
def cache_limpia():
    from django.core.cache import cache

    cache.clear()


@pytest.fixture
def con_correo(ciudadano):
    ciudadano.email = "ana@example.com"
    ciudadano.save()
    return ciudadano


def _pedir_codigo(api, email="ana@example.com"):
    with mock.patch("apps.usuarios.views.enviar_codigo_recuperacion.delay") as delay:
        r = api.post("/api/auth/recuperar/", {"email": email})
    assert r.status_code == 200
    return delay


def test_la_solicitud_responde_igual_exista_o_no_el_correo(api, con_correo):
    existe = _pedir_codigo(api, "ANA@example.com")
    no_existe = _pedir_codigo(api, "nadie@example.com")
    existe.assert_called_once()
    assert existe.call_args.args[:2] == ("ana@example.com", con_correo.username)
    no_existe.assert_not_called()


def test_el_codigo_cambia_la_contrasena_y_cierra_las_sesiones(api, con_correo):
    sesion = RefreshToken.for_user(con_correo)
    codigo = _pedir_codigo(api).call_args.args[2]

    r = api.post("/api/auth/recuperar/confirmar/", {"email": "ana@example.com", "codigo": codigo, "password": NUEVA})
    assert r.status_code == 200
    con_correo.refresh_from_db()
    assert con_correo.check_password(NUEVA)
    assert api.post("/api/auth/token/refresh/", {"refresh": str(sesion)}).status_code == 401
    # Un solo uso.
    r = api.post("/api/auth/recuperar/confirmar/", {"email": "ana@example.com", "codigo": codigo, "password": NUEVA})
    assert r.status_code == 400


def test_cinco_codigos_errados_invalidan_el_codigo(api, con_correo):
    codigo = _pedir_codigo(api).call_args.args[2]
    errado = {"email": "ana@example.com", "codigo": f"{(int(codigo) + 1) % 10**6:06d}", "password": NUEVA}
    for _ in range(recuperacion.INTENTOS_MAXIMOS):
        r = api.post("/api/auth/recuperar/confirmar/", errado)
        assert r.status_code == 400 and "codigo" in r.data
    r = api.post("/api/auth/recuperar/confirmar/", {"email": "ana@example.com", "codigo": codigo, "password": NUEVA})
    assert r.status_code == 400
    con_correo.refresh_from_db()
    assert not con_correo.check_password(NUEVA)


def test_una_contrasena_debil_no_gasta_el_codigo(api, con_correo):
    codigo = _pedir_codigo(api).call_args.args[2]
    r = api.post("/api/auth/recuperar/confirmar/", {"email": "ana@example.com", "codigo": codigo, "password": "123"})
    assert r.status_code == 400 and "password" in r.data
    r = api.post("/api/auth/recuperar/confirmar/", {"email": "ana@example.com", "codigo": codigo, "password": NUEVA})
    assert r.status_code == 200


def test_una_cuenta_recibe_como_maximo_tres_codigos_por_hora(api, con_correo):
    """Límite por cuenta: el de la IP se evade cambiando de IP."""
    for _ in range(recuperacion.CODIGOS_POR_HORA):
        _pedir_codigo(api).assert_called_once()
    _pedir_codigo(api).assert_not_called()


def test_cuenta_eliminada_no_recibe_codigo(api, con_correo):
    con_correo.is_active = False
    con_correo.save()
    _pedir_codigo(api).assert_not_called()


def test_el_correo_lleva_el_codigo():
    enviar_codigo_recuperacion("ana@example.com", "ana", "123456")
    assert len(mail.outbox) == 1
    assert "123456" in mail.outbox[0].body and mail.outbox[0].to == ["ana@example.com"]
