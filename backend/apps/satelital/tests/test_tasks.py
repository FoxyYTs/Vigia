"""Tests de la tarea de Celery `sincronizar_focos` (sin red)."""

from datetime import datetime, timezone
from unittest.mock import patch

import pytest
from django.contrib.gis.geos import Point

from apps.satelital import tasks
from apps.satelital.models import FocoIncendio

pytestmark = pytest.mark.django_db


class _Fuente:
    def __init__(self, resultado=None, error=None):
        self._resultado, self._error = resultado, error

    def __call__(self):
        return self

    def sincronizar(self):
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


def _foco(lon, lat):
    return FocoIncendio.objects.create(
        fuente=FocoIncendio.Fuente.NASA_FIRMS,
        ubicacion=Point(lon, lat, srid=4326),
        fecha_hora=datetime(2026, 10, 30, tzinfo=timezone.utc),
        confianza="n",
    )


class _FuenteQueInserta(_Fuente):
    def sincronizar(self):
        _foco(-75.0, 6.0)
        _foco(-74.0, 5.0)
        return 2


def test_sincronizar_focos_solo_evalua_los_focos_nuevos():
    _foco(-75.5, 6.5)  # ya estaba antes de sincronizar: no genera alerta
    with patch.object(tasks, "FUENTES_TIEMPO_REAL", (("A", _FuenteQueInserta()),)), patch.object(
        tasks.MotorAlertas, "evaluar_foco_nuevo", return_value=object()
    ) as evaluar:
        assert tasks.sincronizar_focos() == {"A": 2, "alertas": 2}
    assert [f.ubicacion.x for f in (c.args[0] for c in evaluar.call_args_list)] == [-75.0, -74.0]
