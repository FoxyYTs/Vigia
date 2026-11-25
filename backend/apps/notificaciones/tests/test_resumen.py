from datetime import timedelta
from unittest.mock import patch

import pytest
from django.contrib.gis.geos import Point
from django.utils import timezone

from apps.alertas.models import Alerta
from apps.notificaciones import despachador
from apps.notificaciones.models import Notificacion
from apps.notificaciones.tasks import enviar_resumen_satelital
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

pytestmark = pytest.mark.django_db

Tipo, Canal, Estado = Alerta.TipoDisparador, Notificacion.Canal, Notificacion.Estado


@pytest.fixture(autouse=True)
def telegram(settings):
    settings.TELEGRAM_BOT_TOKEN = "123:abc"
    settings.TELEGRAM_CANAL_PRIVADO_ID = "@privado"


@pytest.fixture
def satelital():
    n = iter(range(1000))

    def _crear(municipio=None, tipo=Tipo.DETECCION_SATELITAL, hace=timedelta(0)):
        punto = Point(-75 + next(n) * 0.01, 6, srid=4326)
        foco = FocoIncendio.objects.create(
            fuente=FocoIncendio.Fuente.NASA_FIRMS, ubicacion=punto, fecha_hora=timezone.now() - hace
        )
        alerta = Alerta.objects.create(tipo_disparador=tipo, ubicacion=punto, foco=foco, municipio=municipio)
        if hace:
            Alerta.objects.filter(pk=alerta.pk).update(fecha_creacion=timezone.now() - hace)
        return alerta

    return _crear


def _enviar(ok=True):
    with patch.object(despachador.NotificadorTelegram, "enviar_texto", return_value=ok) as enviar:
        total = enviar_resumen_satelital.apply().get()
    return total, enviar


def test_un_solo_mensaje_silencioso_para_todas_las_detecciones(satelital):
    vichada = Municipio.objects.create(nombre="Cumaribo", departamento="Vichada")
    meta = Municipio.objects.create(nombre="Puerto Gaitán", departamento="Meta")
    for m in [vichada, vichada, meta, None]:
        satelital(m)

    total, enviar = _enviar()
    assert total == 4
    enviar.assert_called_once()
    destino, texto, _ = enviar.call_args.args
    assert destino == "@privado" and enviar.call_args.kwargs == {"silencioso": True}
    assert "4 posibles incendios" in texto and "• Vichada: 2" in texto and "Cumaribo (Vichada): 2" in texto
    assert "zona fronteriza o mar): 1" in texto
    assert Notificacion.objects.filter(canal=Canal.TELEGRAM_PRIVADO, estado=Estado.ENVIADO).count() == 4


def test_lo_ya_avisado_no_se_repite_y_sin_pendientes_no_se_envia_nada(satelital):
    satelital()
    _enviar()
    total, enviar = _enviar()
    assert total == 0
    enviar.assert_not_called()


def test_solo_entran_las_satelitales_de_las_ultimas_24_horas(satelital):
    satelital()
    satelital(hace=timedelta(hours=30))
    satelital(tipo=Tipo.VALIDACION_MANUAL)
    total, _ = _enviar()
    assert total == 1


def test_un_resumen_fallido_se_reintenta_en_el_siguiente(satelital):
    satelital()
    with patch.object(enviar_resumen_satelital, "retry", side_effect=enviar_resumen_satelital.MaxRetriesExceededError):
        assert _enviar(ok=False)[0] == 0
    assert Notificacion.objects.get().estado == Estado.FALLIDO
    assert _enviar()[0] == 1
    assert Notificacion.objects.get().estado == Estado.ENVIADO  # la misma fila, no una nueva


def test_las_listas_largas_se_recortan(satelital):
    for i in range(despachador.MAXIMO_LINEAS_RESUMEN + 3):
        satelital(Municipio.objects.create(nombre=f"M{i}", departamento=f"D{i}"))
    texto = despachador.resumen_satelital(list(Alerta.objects.select_related("foco", "municipio")))
    assert "• Otros 3: 3" in texto and len(texto) < 4096
