import pytest

from apps.alertas.models import Alerta
from apps.notificaciones.models import Notificacion

pytestmark = pytest.mark.django_db


@pytest.fixture
def alerta(foco):
    return Alerta.objects.create(
        tipo_disparador=Alerta.TipoDisparador.DETECCION_SATELITAL, foco=foco, ubicacion=foco.ubicacion
    )


def test_notificacion_nueva_queda_enviada(alerta, ciudadano):
    n = Notificacion.objects.create(alerta=alerta, usuario=ciudadano, canal=Notificacion.Canal.PUSH_APP)
    assert n.estado == Notificacion.Estado.ENVIADO
    assert n.fecha_envio is not None and n.fecha_lectura is None


def test_canal_publico_de_telegram_no_tiene_usuario(alerta):
    n = Notificacion.objects.create(alerta=alerta, canal=Notificacion.Canal.TELEGRAM_PUBLICO)
    assert n.usuario is None


def test_borrar_la_alerta_borra_sus_notificaciones(alerta, ciudadano):
    Notificacion.objects.create(alerta=alerta, usuario=ciudadano, canal=Notificacion.Canal.PUSH_APP)
    alerta.delete()
    assert Notificacion.objects.count() == 0
