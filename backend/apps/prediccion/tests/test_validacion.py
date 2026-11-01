from datetime import date, datetime, UTC
from unittest.mock import patch

import pandas as pd
import pytest
from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from django.core.management import call_command

from apps.historico.models import IncendioReportado
from apps.prediccion import validacion
from apps.prediccion.validacion import agregar_por_municipio, celdas_por_municipio
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

# Fila y=61 (6,1°–6,2°) se quema cada enero; la y=63 nunca.
CON_FUEGO = [(-754, 61), (-753, 61)]
SIN_FUEGO = [(-754, 63), (-753, 63)]
CELDAS = pd.DataFrame(CON_FUEGO + SIN_FUEGO, columns=["x", "y"])


def _cuadro(x0, y0, x1, y1):
    return MultiPolygon(Polygon(((x0, y0), (x0, y1), (x1, y1), (x1, y0), (x0, y0))), srid=4326)


@pytest.fixture
def municipios(db):
    # Rionegro cubre la fila con fuego; Marinilla la fila sin fuego.
    return (
        Municipio.objects.create(nombre="Rionegro", departamento="Antioquia", codigo_dane="05615",
                                 geom=_cuadro(-75.4, 6.11, -75.21, 6.19)),
        Municipio.objects.create(nombre="Marinilla", departamento="Antioquia", codigo_dane="05440",
                                 geom=_cuadro(-75.4, 6.31, -75.21, 6.39)),
    )


@pytest.fixture
def historia(municipios):
    rionegro, _ = municipios
    FocoIncendio.objects.bulk_create(
        FocoIncendio(
            fuente=FocoIncendio.Fuente.NASA_FIRMS,
            ubicacion=Point((x + 0.5) * 0.1, (y + 0.5) * 0.1, srid=4326),
            fecha_hora=datetime(anio, 1, 10, tzinfo=UTC),
            confianza="n",
        )
        for anio in range(2019, 2025)
        for x, y in CON_FUEGO
    )
    # Rionegro reporta un incendio cada enero; en 2024 también uno en julio sin detección.
    IncendioReportado.objects.bulk_create(
        [IncendioReportado(dataset="t", codigo=f"e{a}", fecha=date(a, 1, 20), evento="INCENDIO FORESTAL",
                           municipio=rionegro) for a in range(2019, 2025)]
        + [IncendioReportado(dataset="t", codigo="jul", fecha=date(2024, 7, 5), evento="INCENDIO FORESTAL",
                             municipio=rionegro)]
    )
    with patch.object(validacion, "celdas_colombia", return_value=CELDAS):
        yield


def test_agregado_es_la_probabilidad_de_al_menos_una_deteccion():
    celda_mes = pd.DataFrame({
        "c": [0, 1], "p": [pd.Period("2023-01", "M")] * 2,
        "puntaje": [0.5, 0.5], "base": [0.2, 0.0], "fuego": [1.0, 0.0],
    })
    r = agregar_por_municipio(celda_mes, pd.DataFrame({"c": [0, 1], "municipio": [7, 7]}))
    assert r.loc[0, "puntaje"] == pytest.approx(0.75)
    assert r.loc[0, "base"] == pytest.approx(0.2)
    assert r.loc[0, "firms"] == 1


@pytest.mark.django_db
def test_una_celda_toca_todos_los_municipios_que_intersecta(municipios):
    rionegro, marinilla = municipios
    # La celda (-754, 62) abarca 6,2°–6,3°: no toca a ninguno; la (-754, 61) solo a Rionegro.
    pares = celdas_por_municipio(pd.DataFrame([(-754, 61), (-754, 62), (-754, 63)], columns=["x", "y"]))
    assert set(map(tuple, pares.to_numpy())) == {(0, rionegro.pk), (2, marinilla.pk)}


@pytest.mark.django_db
def test_validar_contra_ungrd(historia):
    r = validacion.validar()
    assert r["evaluacion"] == "2023-01..2024-12" and r["municipios"] == 2
    assert r["municipios_que_reportan"] == 1

    h1 = r["horizontes"]["1"]
    # 2 municipios × 24 meses; Rionegro reporta 3 de esos meses (dos eneros y un julio).
    assert h1["todos"]["municipio_mes"] == 48 and h1["todos"]["prevalencia_ungrd"] == pytest.approx(3 / 48, abs=1e-4)
    # Los dos eneros quedan arriba; el incendio de julio, sin detección previa, no
    # lo anticipa nadie. Ese tipo de caso es justo lo que mide esta validación.
    assert 0.6 < h1["todos"]["gradient_boosting"]["auc"] < 1
    assert h1["solo_municipios_que_reportan"]["municipio_mes"] == 24

    c = r["concordancia_firms_ungrd"]
    assert (c["firms_y_ungrd"], c["solo_ungrd"], c["solo_firms"]) == (2, 1, 0)
    assert c["ungrd_con_deteccion"] == pytest.approx(2 / 3, abs=1e-4)


@pytest.mark.django_db
def test_comando_guarda_el_json(historia, tmp_path, capsys):
    salida = tmp_path / "validacion.json"
    call_command("validar_modelo_ungrd", salida=str(salida))
    assert "Concordancia FIRMS" in capsys.readouterr().out
    assert '"horizontes"' in salida.read_text()
