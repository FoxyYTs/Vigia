"""
Tests de ClienteNasaFirms.

`test_parsear_fila_firms_*` no dependen de GDAL/GEOS/base de datos —
prueban la función pura. `test_sincronizar_*` sí requieren Django+GDAL
completos (necesitan `Point` y el ORM) — no se pudieron ejecutar en el
entorno donde se escribió este archivo (sin GDAL instalado fuera de
Docker), pero la lógica de parseo que usan sí se validó por separado
contra las 524 filas reales de `fixtures/firms_sample.csv` antes de
escribir este archivo. Correr con `pytest` dentro del contenedor
`backend` para la verificación completa.
"""

import csv
from pathlib import Path

import pytest
import responses

from apps.satelital.clientes import COLOMBIA_BBOX, ClienteNasaFirms, parsear_fila_firms

FIXTURE_CSV = Path(__file__).parent / "fixtures" / "firms_sample.csv"


def _filas_fixture():
    with open(FIXTURE_CSV) as f:
        return list(csv.DictReader(f))


def test_parsear_fila_firms_contra_datos_reales():
    """
    fixtures/firms_sample.csv es una respuesta real de la API (capturada
    09-sep-2026, 524 detecciones VIIRS_NOAA20_NRT en Colombia) — no datos
    sintéticos, para no validar el parser contra suposiciones propias
    sobre el formato.
    """
    filas = _filas_fixture()
    assert len(filas) == 524

    resultados = [parsear_fila_firms(f, "NASA_FIRMS") for f in filas]

    # confidence de VIIRS es categórico, no numérico — ver docstring de
    # parsear_fila_firms y FocoIncendio.confianza.
    assert {r["confianza"] for r in resultados} == {"l", "n", "h"}

    for r in resultados:
        assert COLOMBIA_BBOX[0] - 1 <= r["longitud"] <= COLOMBIA_BBOX[2] + 1
        assert COLOMBIA_BBOX[1] - 1 <= r["latitud"] <= COLOMBIA_BBOX[3] + 1
        assert r["fecha_hora"].tzinfo is not None
        assert r["satelite"] == "N20"


@pytest.mark.parametrize(
    "acq_time,hora_esperada,minuto_esperado",
    [
        ("58", 0, 58),  # sin padding — formato real de FIRMS para < 10:00
        ("622", 6, 22),
        ("1345", 13, 45),
        ("0000", 0, 0),
    ],
)
def test_parsear_fila_firms_acq_time_sin_padding(acq_time, hora_esperada, minuto_esperado):
    fila = {
        "latitude": "4.5",
        "longitude": "-74.0",
        "acq_date": "2026-09-09",
        "acq_time": acq_time,
        "confidence": "n",
        "frp": "1.5",
        "satellite": "N20",
    }
    resultado = parsear_fila_firms(fila, "NASA_FIRMS")
    assert resultado["fecha_hora"].hour == hora_esperada
    assert resultado["fecha_hora"].minute == minuto_esperado


@pytest.mark.django_db
@responses.activate
def test_sincronizar_persiste_focos_nuevos():
    cliente = ClienteNasaFirms(map_key="clave-de-prueba")
    responses.add(responses.GET, cliente._url(1), body=FIXTURE_CSV.read_text(), status=200)

    nuevos = cliente.sincronizar(dias=1)

    assert nuevos == 524


@pytest.mark.django_db
@responses.activate
def test_sincronizar_no_duplica_en_segunda_corrida():
    """La UniqueConstraint (fuente, ubicacion, fecha_hora) + get_or_create
    deben evitar duplicados si Celery Beat corre dos veces sobre el mismo
    rango de días (ej. tras un reintento)."""
    cliente = ClienteNasaFirms(map_key="clave-de-prueba")
    responses.add(responses.GET, cliente._url(1), body=FIXTURE_CSV.read_text(), status=200)
    responses.add(responses.GET, cliente._url(1), body=FIXTURE_CSV.read_text(), status=200)

    primera = cliente.sincronizar(dias=1)
    segunda = cliente.sincronizar(dias=1)

    assert primera == 524
    assert segunda == 0


@responses.activate
def test_descargar_csv_detecta_map_key_invalida():
    cliente = ClienteNasaFirms(map_key="clave-invalida")
    responses.add(responses.GET, cliente._url(1), body="Invalid API call.", status=200)

    with pytest.raises(ValueError, match="MAP_KEY"):
        cliente._descargar_csv(1)


def test_descargar_historico_no_implementado():
    cliente = ClienteNasaFirms(map_key="clave-de-prueba")
    with pytest.raises(NotImplementedError):
        cliente.descargar_historico()
