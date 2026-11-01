from unittest.mock import Mock, patch

import pytest
import requests

from apps.alertas.models import Alerta
from apps.notificaciones.despachador import DespachadorNotificaciones, NotificadorTelegram
from apps.notificaciones.models import Notificacion
from apps.notificaciones.tasks import despachar_alerta

pytestmark = pytest.mark.django_db

Tipo, Canal, Estado = Alerta.TipoDisparador, Notificacion.Canal, Notificacion.Estado


@pytest.fixture(autouse=True)
def telegram(settings):
    settings.TELEGRAM_BOT_TOKEN = "123:abc"
    settings.TELEGRAM_CANAL_PUBLICO_ID = "@publico"
    settings.TELEGRAM_CANAL_PRIVADO_ID = "@privado"
    settings.TELEGRAM_CANAL_INTERNO_ID = "@interno"
    return settings


@pytest.fixture
def crear_alerta(foco):
    def _crear(tipo):
        return Alerta.objects.create(tipo_disparador=tipo, foco=foco, ubicacion=foco.ubicacion)

    return _crear


@pytest.mark.parametrize(
    "tipo, canales",
    [
        (Tipo.DETECCION_SATELITAL, {Canal.TELEGRAM_PRIVADO}),
        (Tipo.COINCIDENCIA_GEOGRAFICA, {Canal.TELEGRAM_PUBLICO, Canal.TELEGRAM_PRIVADO}),
        (Tipo.VALIDACION_MANUAL, {Canal.TELEGRAM_PUBLICO, Canal.TELEGRAM_PRIVADO}),
        (Tipo.ACUMULACION_REPORTES, {Canal.TELEGRAM_PRIVADO, Canal.TELEGRAM_INTERNO}),
    ],
)
def test_ruteo_por_tipo_de_alerta(crear_alerta, tipo, canales):
    notificador = Mock(enviar=Mock(return_value=True))
    notificaciones = DespachadorNotificaciones(notificador).despachar(crear_alerta(tipo))
    assert {n.canal for n in notificaciones} == canales
    assert all(n.estado == Estado.ENVIADO and n.usuario is None for n in notificaciones)


def test_envio_fallido_queda_registrado(crear_alerta):
    notificador = Mock(enviar=Mock(return_value=False))
    [n] = DespachadorNotificaciones(notificador).despachar(crear_alerta(Tipo.DETECCION_SATELITAL))
    assert n.estado == Estado.FALLIDO


def test_reintento_no_repite_canales_ya_enviados(crear_alerta):
    alerta = crear_alerta(Tipo.COINCIDENCIA_GEOGRAFICA)
    Notificacion.objects.create(alerta=alerta, canal=Canal.TELEGRAM_PUBLICO)
    notificador = Mock(enviar=Mock(return_value=True))
    [n] = DespachadorNotificaciones(notificador).despachar(alerta)
    assert n.canal == Canal.TELEGRAM_PRIVADO


def test_telegram_sin_token_no_envia_nada(telegram, crear_alerta):
    telegram.TELEGRAM_BOT_TOKEN = ""
    with patch("apps.notificaciones.despachador.requests.post") as post:
        assert NotificadorTelegram().enviar(crear_alerta(Tipo.DETECCION_SATELITAL), "@privado") is False
    post.assert_not_called()


def test_telegram_envia_el_mensaje_al_canal(crear_alerta):
    alerta = crear_alerta(Tipo.DETECCION_SATELITAL)
    with patch("apps.notificaciones.despachador.requests.post", return_value=Mock(ok=True)) as post:
        assert NotificadorTelegram().enviar(alerta, "@privado") is True
    url, cuerpo = post.call_args.args[0], post.call_args.kwargs["json"]
    assert url == "https://api.telegram.org/bot123:abc/sendMessage"
    assert cuerpo["chat_id"] == "@privado"
    assert "Detección satelital" in cuerpo["text"] and "openstreetmap.org" in cuerpo["text"]


def test_telegram_caido_no_rompe_el_despacho(crear_alerta):
    with patch(
        "apps.notificaciones.despachador.requests.post", side_effect=requests.ConnectionError
    ):
        assert NotificadorTelegram().enviar(crear_alerta(Tipo.DETECCION_SATELITAL), "@privado") is False


def test_tarea_sin_token_no_reintenta(telegram, crear_alerta):
    telegram.TELEGRAM_BOT_TOKEN = ""
    alerta = crear_alerta(Tipo.DETECCION_SATELITAL)
    assert despachar_alerta.apply(args=[alerta.pk]).get() == 0
    assert Notificacion.objects.get().estado == Estado.FALLIDO


def test_tarea_reintenta_hasta_el_maximo_si_telegram_falla(crear_alerta):
    alerta = crear_alerta(Tipo.DETECCION_SATELITAL)
    with patch.object(NotificadorTelegram, "enviar", return_value=False):
        assert despachar_alerta.apply(args=[alerta.pk]).get() == 0
    assert Notificacion.objects.filter(estado=Estado.FALLIDO).count() == 1 + despachar_alerta.max_retries
