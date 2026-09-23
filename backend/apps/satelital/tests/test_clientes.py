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
import json
import re
from datetime import date
from pathlib import Path

import pytest
import responses

from apps.satelital.clientes import (
    COLOMBIA_BBOX,
    ClienteInpeQueimadas,
    ClienteNasaFirms,
    parsear_feature_inpe,
    parsear_fila_firms,
    ventanas_de_dias,
)
from apps.satelital.models import FocoIncendio

FIXTURE_CSV = Path(__file__).parent / "fixtures" / "firms_sample.csv"
FIXTURE_INPE = Path(__file__).parent / "fixtures" / "inpe_sample.json"


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


# --- Histórico FIRMS -------------------------------------------------------


def test_ventanas_de_dias_parte_en_bloques_de_cinco():
    ventanas = list(ventanas_de_dias(date(2026, 1, 1), date(2026, 1, 12)))
    assert ventanas == [
        (date(2026, 1, 1), 5),
        (date(2026, 1, 6), 5),
        (date(2026, 1, 11), 2),
    ]


def test_ventanas_de_dias_un_solo_dia():
    assert list(ventanas_de_dias(date(2026, 1, 1), date(2026, 1, 1))) == [(date(2026, 1, 1), 1)]


def test_ventanas_de_dias_rechaza_rango_invertido():
    with pytest.raises(ValueError):
        list(ventanas_de_dias(date(2026, 1, 2), date(2026, 1, 1)))


def test_url_historica_incluye_sensor_y_fecha():
    cliente = ClienteNasaFirms(map_key="clave-de-prueba")
    url = cliente._url(5, date(2020, 3, 1), "VIIRS_NOAA20_SP")
    assert url.endswith("/VIIRS_NOAA20_SP/-79.0,-4.3,-66.8,13.5/5/2020-03-01")


@pytest.mark.django_db
@responses.activate
def test_descargar_historico_recorre_ventanas_y_es_idempotente():
    cliente = ClienteNasaFirms(map_key="clave-de-prueba")
    desde, hasta = date(2026, 9, 1), date(2026, 9, 7)  # ventanas: 5 días + 2 días
    sensor = "VIIRS_NOAA20_SP"
    cuerpo = FIXTURE_CSV.read_text()
    vacio = cuerpo.splitlines()[0] + "\n"  # solo encabezado: ventana sin focos
    responses.add(responses.GET, cliente._url(5, date(2026, 9, 1), sensor), body=cuerpo)
    responses.add(responses.GET, cliente._url(2, date(2026, 9, 6), sensor), body=vacio)

    nuevos = cliente.descargar_historico(desde, hasta, pausa=0)
    assert nuevos == 524

    responses.add(responses.GET, cliente._url(5, date(2026, 9, 1), sensor), body=cuerpo)
    responses.add(responses.GET, cliente._url(2, date(2026, 9, 6), sensor), body=vacio)
    assert cliente.descargar_historico(desde, hasta, pausa=0) == 0
    assert FocoIncendio.objects.count() == 524


# --- INPE QUEIMADAS --------------------------------------------------------


def _features_inpe():
    return json.loads(FIXTURE_INPE.read_text())["features"]


def test_parsear_feature_inpe_contra_datos_reales():
    """inpe_sample.json es una respuesta real del WFS (23-sep-2026, capa
    bdqueimadas2:focos, pais='Colombia'), con 8 focos por satélite."""
    features = _features_inpe()
    assert len(features) == 71

    resultados = [parsear_feature_inpe(f) for f in features]

    assert {r["fuente"] for r in resultados} == {"INPE_QUEIMADAS"}
    assert {"GOES-19", "NOAA-20", "NPP-375", "AQUA_M-T"} <= {r["satelite"] for r in resultados}
    for r in resultados:
        assert r["confianza"] == ""  # INPE no entrega confianza
        assert r["fecha_hora"].tzinfo is not None
        assert -80 <= r["longitud"] <= -66 and -5 <= r["latitud"] <= 14


def test_parsear_feature_inpe_frp_nulo():
    feature = {
        "properties": {
            "data_hora_gmt": "2026-09-23T20:10:00Z",
            "latitude": 4.5,
            "longitude": -74.0,
            "satelite": "GOES-19",
            "frp": None,
        }
    }
    assert parsear_feature_inpe(feature)["brillo_frp"] is None


def test_params_inpe_filtra_por_pais_y_fecha():
    from datetime import datetime, timezone

    cliente = ClienteInpeQueimadas(url="https://wfs.test/wfs")
    params = cliente._params(datetime(2026, 9, 22, 12, 0, tzinfo=timezone.utc), 0)
    assert params["cql_filter"] == "pais='Colombia' AND data_hora_gmt >= 2026-09-22T12:00:00Z"
    assert params["typeNames"] == "bdqueimadas2:focos"


@pytest.mark.django_db
@responses.activate
def test_inpe_sincronizar_persiste_y_no_duplica():
    cliente = ClienteInpeQueimadas(url="https://wfs.test/wfs")
    respuesta = json.dumps({"type": "FeatureCollection", "features": _features_inpe()})
    responses.add(responses.GET, re.compile(r"https://wfs\.test/wfs.*"), body=respuesta)

    primera = cliente.sincronizar(dias=1)
    segunda = cliente.sincronizar(dias=1)

    assert primera == 71
    assert segunda == 0


@pytest.mark.django_db
@responses.activate
def test_inpe_sincronizar_pagina_hasta_agotar():
    cliente = ClienteInpeQueimadas(url="https://wfs.test/wfs")
    cliente.TAMANO_PAGINA = 40
    features = _features_inpe()
    pagina1 = json.dumps({"features": features[:40]})
    pagina2 = json.dumps({"features": features[40:]})
    responses.add(responses.GET, re.compile(r"https://wfs\.test/wfs.*startIndex=0.*"), body=pagina1)
    responses.add(responses.GET, re.compile(r"https://wfs\.test/wfs.*startIndex=40.*"), body=pagina2)

    assert cliente.sincronizar(dias=1) == 71
