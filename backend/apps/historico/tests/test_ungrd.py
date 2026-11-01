"""ClienteUngrd y la API de incendios reportados, con filas reales grabadas
de datos.gov.co (fixtures/ungrd_*.json)."""

import json
from datetime import date
from pathlib import Path

import pytest
import responses

from apps.historico.clientes import ClienteUngrd, parsear_fila_ungrd
from apps.historico.models import IncendioReportado
from apps.usuarios.models import Municipio

FIXTURES = Path(__file__).parent / "fixtures"


def _filas(dataset):
    return json.loads((FIXTURES / f"ungrd_{dataset}.json").read_text())


@pytest.fixture
def municipios(db):
    for codigo, nombre, depto in (
        ("05044", "Anzá", "Antioquia"),
        ("05615", "Rionegro", "Antioquia"),
        ("85263", "Pore", "Casanare"),
        ("25151", "Cáqueza", "Cundinamarca"),
    ):
        Municipio.objects.create(codigo_dane=codigo, nombre=nombre, departamento=depto)


@pytest.fixture
def api_ungrd():
    with responses.RequestsMock() as rsps:
        for dataset in ("wwkg-r6te", "rgre-6ak4"):
            rsps.get(f"https://www.datos.gov.co/resource/{dataset}.json", json=_filas(dataset))
        yield rsps


def test_parsear_completa_el_cero_inicial_del_codigo_dane():
    fila = parsear_fila_ungrd(_filas("wwkg-r6te")[1], "divipola")
    assert fila == {
        "codigo": "row-dyq9.yyca-knii",
        "fecha": date(2019, 1, 1),
        "evento": "INCENDIO DE COBERTURA VEGETAL",
        "codigo_dane": "05044",
        "municipio_reportado": "ANZA, ANTIOQUIA",
        "hectareas": 6.0,
    }


def test_parsear_codigo_cero_y_hectareas_con_coma():
    assert parsear_fila_ungrd(_filas("wwkg-r6te")[0], "divipola")["codigo_dane"] is None
    fila = {":id": "x", "fecha": "2023-03-01T00:00:00.000", "evento": "INCENDIO FORESTAL", "hectareas": "2,5"}
    assert parsear_fila_ungrd(fila, "divipola")["hectareas"] == 2.5


def test_sincronizar_guarda_con_municipio_y_es_idempotente(municipios, api_ungrd, settings):
    settings.UNGRD_SOCRATA_APP_TOKEN = "token-de-prueba"

    assert ClienteUngrd().sincronizar() == 6
    assert ClienteUngrd().sincronizar() == 0

    assert IncendioReportado.objects.filter(municipio__codigo_dane="05615").count() == 2
    sin_municipio = IncendioReportado.objects.get(municipio=None)
    assert sin_municipio.municipio_reportado == "INIRIDA, GUAINIA"
    peticion = api_ungrd.calls[0].request
    assert peticion.headers["X-App-Token"] == "token-de-prueba"
    assert "INCENDIO+FORESTAL" in peticion.url and "%24order=%3Aid" in peticion.url


def test_pagina_hasta_recibir_una_pagina_incompleta(municipios):
    with responses.RequestsMock() as rsps:
        url = "https://www.datos.gov.co/resource/{}.json"
        filas = _filas("rgre-6ak4")
        rsps.get(url.format("wwkg-r6te"), json=[])
        rsps.get(url.format("rgre-6ak4"), json=filas[:2])
        # responses repite la última respuesta registrada: la segunda página
        # debe venir incompleta para que el cliente pare.
        rsps.get(url.format("rgre-6ak4"), json=filas[2:3])
        cliente = ClienteUngrd()
        cliente.TAMANO_PAGINA = 2
        assert cliente.sincronizar() == 3
        assert "%24offset=2" in rsps.calls[2].request.url


@pytest.fixture
def cargados(municipios, api_ungrd):
    ClienteUngrd().sincronizar()


def test_api_filtra_por_anio_y_municipio(api, cargados):
    assert api.get("/api/incendios-reportados/?anio=2023").data["count"] == 4
    r = api.get("/api/incendios-reportados/?municipio=05615").data["results"]
    assert {x["municipio"] for x in r} == {"Rionegro, Antioquia"} and len(r) == 2
    assert api.get("/api/incendios-reportados/?anio=dos-mil").status_code == 400


def test_api_agrega_por_municipio(api, cargados):
    filas = api.get("/api/incendios-reportados/por-municipio/?anio=2023").data
    assert filas[0] == {"codigo_dane": "05615", "municipio": "Rionegro, Antioquia", "incendios": 2, "hectareas": 0.0}
    assert {f["codigo_dane"] for f in filas} == {"05615", "85263", "25151"}


def test_comando_resume_la_carga_por_anio(municipios, api_ungrd, capsys):
    from django.core.management import call_command

    call_command("cargar_incendios_ungrd")
    salida = capsys.readouterr().out
    assert "Nuevos: 6. Total: 6. Sin municipio: 1." in salida
    assert "2023: 4" in salida
