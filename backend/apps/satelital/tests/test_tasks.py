"""Tests de la tarea de Celery `sincronizar_focos` (sin red ni base de datos)."""

from unittest.mock import patch

from apps.satelital import tasks


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
        assert tasks.sincronizar_focos() == {"A": 3, "B": 7}


def test_sincronizar_focos_una_fuente_caida_no_bloquea_a_las_demas():
    fuentes = (("A", _Fuente(error=RuntimeError("caída"))), ("B", _Fuente(7)))
    with patch.object(tasks, "FUENTES_TIEMPO_REAL", fuentes):
        assert tasks.sincronizar_focos() == {"A": None, "B": 7}
