"""Tests de la tarea de Celery `sincronizar_focos` (sin red)."""

from datetime import timedelta
from unittest.mock import patch

import pytest
from django.contrib.gis.geos import Point
from django.utils import timezone

from apps.satelital import tasks
from apps.satelital.models import FocoIncendio

pytestmark = pytest.mark.django_db


class _Fuente:
    FUENTE = FocoIncendio.Fuente.NASA_FIRMS

    def __init__(self, resultado=None, error=None):
        self._resultado, self._error = resultado, error

    def __call__(self):
        return self

    def sincronizar(self, dias):
        if self._error:
            raise self._error
        return self._resultado


def test_sincronizar_focos_reporta_nuevos_por_fuente():
    fuentes = (("A", _Fuente(3)), ("B", _Fuente(7)))
    with patch.object(tasks, "FUENTES_TIEMPO_REAL", fuentes):
        assert tasks.sincronizar_focos() == {"A": 3, "B": 7, "alertas": 0}


def test_sincronizar_focos_una_fuente_caida_no_bloquea_a_las_demas():
    fuentes = (("A", _Fuente(error=RuntimeError("caída"))), ("B", _Fuente(7)))
    with patch.object(tasks, "FUENTES_TIEMPO_REAL", fuentes):
        assert tasks.sincronizar_focos() == {"A": None, "B": 7, "alertas": 0}


def _foco(lon, lat, hace=timedelta(hours=2), fuente=FocoIncendio.Fuente.NASA_FIRMS):
    return FocoIncendio.objects.create(
        fuente=fuente,
        ubicacion=Point(lon, lat, srid=4326),
        fecha_hora=timezone.now() - hace,
        confianza="n",
    )


class _FuenteQueInserta(_Fuente):
    def sincronizar(self, dias):
        _foco(-75.0, 6.0)
        _foco(-74.0, 5.0)
        _foco(-73.0, 4.0, hace=timedelta(days=3))  # recuperado de una caída: sin alerta
        return 3


def test_sincronizar_focos_solo_evalua_los_focos_nuevos():
    _foco(-75.5, 6.5)  # ya estaba antes de sincronizar: no genera alerta
    with patch.object(tasks, "FUENTES_TIEMPO_REAL", (("A", _FuenteQueInserta()),)), patch.object(
        tasks.MotorAlertas, "evaluar_foco_nuevo", return_value=object()
    ) as evaluar:
        assert tasks.sincronizar_focos() == {"A": 3, "alertas": 2}
    assert [f.ubicacion.x for f in (c.args[0] for c in evaluar.call_args_list)] == [-75.0, -74.0]


def test_dias_a_sincronizar_recupera_desde_el_ultimo_foco_de_la_fuente():
    firms, inpe = FocoIncendio.Fuente.NASA_FIRMS, FocoIncendio.Fuente.INPE_QUEIMADAS
    assert tasks.dias_a_sincronizar(firms) == 1  # sin focos
    _foco(-75.0, 6.0, hace=timedelta(hours=5))
    assert tasks.dias_a_sincronizar(firms) == 1
    _foco(-74.0, 5.0, hace=timedelta(days=11, hours=2), fuente=inpe)
    assert tasks.dias_a_sincronizar(inpe) == 12
    FocoIncendio.objects.filter(fuente=inpe).update(fecha_hora=timezone.now() - timedelta(days=90))
    assert tasks.dias_a_sincronizar(inpe) == tasks.MAX_DIAS_RECUPERACION


def test_sincronizar_focos_pide_los_dias_perdidos_a_cada_fuente():
    _foco(-75.0, 6.0, hace=timedelta(days=4, hours=1))
    pedidos = []

    class _Registra(_Fuente):
        def sincronizar(self, dias):
            pedidos.append(dias)
            return 0

    with patch.object(tasks, "FUENTES_TIEMPO_REAL", (("A", _Registra()),)):
        tasks.sincronizar_focos()
    assert pedidos == [5]
