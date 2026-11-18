from unittest.mock import Mock, patch

import pytest
import requests

from apps.alertas.models import Alerta
from apps.notificaciones.models import Notificacion

pytestmark = pytest.mark.django_db

Canal, Estado = Notificacion.Canal, Notificacion.Estado


@pytest.fixture
def telegram(settings):
    settings.TELEGRAM_BOT_TOKEN = "123:secreto"
    settings.TELEGRAM_CANAL_PUBLICO_ID = "-100111"
    settings.TELEGRAM_CANAL_PRIVADO_ID = "-100222"
    settings.TELEGRAM_CANAL_INTERNO_ID = ""
    return settings


@pytest.fixture
def envios(foco, municipio):
    alerta = Alerta.objects.create(
        tipo_disparador=Alerta.TipoDisparador.COINCIDENCIA_GEOGRAFICA, foco=foco, ubicacion=foco.ubicacion,
        municipio=municipio,
    )
    Notificacion.objects.create(alerta=alerta, canal=Canal.TELEGRAM_PUBLICO)
    Notificacion.objects.create(alerta=alerta, canal=Canal.TELEGRAM_PRIVADO, estado=Estado.FALLIDO)
    Notificacion.objects.create(alerta=alerta, canal=Canal.PUSH_APP)


def _get_me(ok=True):
    return Mock(ok=ok, json=Mock(return_value={"ok": ok, "result": {"username": "VigiaAlertasBot"}}))


def test_estado_del_bot_por_canal_sin_exponer_secretos(api_como, administrador, telegram, envios):
    with patch("apps.notificaciones.views.requests.get", return_value=_get_me()):
        r = api_como(administrador).get("/api/bot-telegram/")
    assert r.status_code == 200
    assert r.data["bot"] == "VigiaAlertasBot" and r.data["token_configurado"]
    canales = {c["canal"]: c for c in r.data["canales"]}
    assert set(canales) == {Canal.TELEGRAM_PUBLICO, Canal.TELEGRAM_PRIVADO, Canal.TELEGRAM_INTERNO}
    assert canales[Canal.TELEGRAM_PUBLICO]["enviados_7d"] == 1
    assert canales[Canal.TELEGRAM_PUBLICO]["ultimo_envio"] is not None
    assert canales[Canal.TELEGRAM_PRIVADO]["fallidos_7d"] == 1
    assert set(canales[Canal.TELEGRAM_PRIVADO]["alertas"]) == set(Alerta.TipoDisparador.values)
    assert not canales[Canal.TELEGRAM_INTERNO]["configurado"]
    assert canales[Canal.TELEGRAM_INTERNO]["alertas"] == [Alerta.TipoDisparador.ACUMULACION_REPORTES]
    # Solo Telegram (el push va a la bandeja de cada usuario), lo más reciente primero.
    assert [n["canal"] for n in r.data["recientes"]] == [Canal.TELEGRAM_PRIVADO, Canal.TELEGRAM_PUBLICO]
    assert r.data["recientes"][0]["municipio"] == "Rionegro"
    for secreto in ("123:secreto", "-100111", "-100222"):
        assert secreto not in r.content.decode()


@pytest.mark.parametrize("respuesta", [_get_me(ok=False), requests.ConnectionError()])
def test_bot_que_no_responde(api_como, staff, telegram, respuesta):
    with patch("apps.notificaciones.views.requests.get", side_effect=[respuesta]):
        assert api_como(staff).get("/api/bot-telegram/").data["bot"] is None


def test_sin_token_no_consulta_telegram(api_como, staff, settings):
    settings.TELEGRAM_BOT_TOKEN = ""
    with patch("apps.notificaciones.views.requests.get") as get:
        r = api_como(staff).get("/api/bot-telegram/")
    get.assert_not_called()
    assert r.data["bot"] is None and not r.data["token_configurado"]


def test_ciudadano_y_anonimo_no_ven_el_bot(api, api_como, ciudadano):
    assert api.get("/api/bot-telegram/").status_code == 401
    assert api_como(ciudadano).get("/api/bot-telegram/").status_code == 403


def test_staff_envia_un_mensaje_de_prueba(api_como, staff, telegram):
    with patch("apps.notificaciones.despachador.requests.post", return_value=Mock(ok=True)) as post:
        r = api_como(staff).post("/api/bot-telegram/probar/", {"canal": Canal.TELEGRAM_PRIVADO}, format="json")
    assert r.status_code == 200
    assert post.call_args.kwargs["json"]["chat_id"] == "-100222"
    assert "staff1" in post.call_args.kwargs["json"]["text"]
    assert not Notificacion.objects.exists()


def test_prueba_a_un_canal_sin_configurar_falla(api_como, staff, telegram):
    with patch("apps.notificaciones.despachador.requests.post") as post:
        r = api_como(staff).post("/api/bot-telegram/probar/", {"canal": Canal.TELEGRAM_INTERNO}, format="json")
    post.assert_not_called()
    assert r.status_code == 502


@pytest.mark.parametrize("canal", ["push_app", "", None])
def test_prueba_con_canal_invalido(api_como, staff, telegram, canal):
    assert api_como(staff).post("/api/bot-telegram/probar/", {"canal": canal}, format="json").status_code == 400


def test_solo_el_staff_envia_pruebas(api_como, administrador, telegram):
    with patch("apps.notificaciones.despachador.requests.post") as post:
        r = api_como(administrador).post("/api/bot-telegram/probar/", {"canal": "telegram_publico"}, format="json")
    assert r.status_code == 403
    post.assert_not_called()
