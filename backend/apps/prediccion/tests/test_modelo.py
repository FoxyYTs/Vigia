from datetime import datetime, UTC
from unittest.mock import patch

import numpy as np
import pandas as pd
import pytest
from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from django.core.management import call_command

from apps.prediccion import modelo
from apps.prediccion.modelo import HORIZONTES, ModeloRecurrencia, construir_panel, variables
from apps.prediccion.models import CorridaModeloML
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

# Celdas de 0,1° cerca de Rionegro: la fila y=61 se quema cada enero; la y=63 nunca.
CON_FUEGO = [(-754, 61), (-753, 61), (-752, 61)]
SIN_FUEGO = [(-754, 63), (-753, 63), (-752, 63)]
CELDAS = pd.DataFrame(CON_FUEGO + SIN_FUEGO, columns=["x", "y"])


def _panel_aleatorio(semilla=0):
    rng = np.random.default_rng(semilla)
    meses = pd.period_range("2019-01", "2022-12", freq="M")
    focos = pd.DataFrame(
        [
            (x, y, p, 1, rng.uniform(1, 50))
            for x, y in CELDAS.itertuples(index=False)
            for p in meses
            if rng.random() < 0.3
        ],
        columns=["x", "y", "p", "n", "frp"],
    )
    return construir_panel(CELDAS, focos, meses, meses[-1])


@pytest.mark.parametrize("h", HORIZONTES)
def test_las_variables_no_ven_meses_posteriores_a_t_menos_h(h):
    panel = _panel_aleatorio()
    objetivo = panel.index[(panel["x"] == -753) & (panel["y"] == 61) & (panel["p"] == pd.Period("2022-06", "M"))][0]
    antes = variables(panel, h).loc[objetivo]

    # Cambiar todo lo que pasa desde t-h+1 en adelante no debe mover las variables del objetivo.
    alterado = panel.copy()
    futuro = alterado["t"] > panel.loc[objetivo, "t"] - h
    alterado.loc[futuro, "fuego"] = 1 - alterado.loc[futuro, "fuego"]
    alterado.loc[futuro, "frp"] = 999.0
    pd.testing.assert_series_equal(variables(alterado, h).loc[objetivo], antes)


def test_los_meses_futuros_quedan_sin_etiqueta():
    meses = pd.period_range("2022-01", "2022-06", freq="M")
    panel = construir_panel(CELDAS, pd.DataFrame(columns=["x", "y", "p", "n", "frp"]), meses, pd.Period("2022-04", "M"))
    assert panel.loc[panel["p"] <= pd.Period("2022-04", "M"), "fuego"].eq(0).all()
    assert panel.loc[panel["p"] > pd.Period("2022-04", "M"), "fuego"].isna().all()


def test_metricas_sin_las_dos_clases_no_se_calculan():
    assert modelo._metricas(np.zeros(5), np.ones(5)) == {"auc": None, "pr_auc": None, "precision_top5": None}


@pytest.fixture
def focos_cada_enero(db):
    FocoIncendio.objects.bulk_create(
        FocoIncendio(
            fuente=FocoIncendio.Fuente.NASA_FIRMS,
            ubicacion=Point((x + 0.5) * 0.1, (y + 0.5) * 0.1, srid=4326),
            fecha_hora=datetime(anio, 1, 15, tzinfo=UTC),
            confianza="n",
        )
        for anio in range(2019, 2026)
        for x, y in CON_FUEGO
    )
    # Ruido que el modelo debe ignorar: baja confianza e INPE.
    FocoIncendio.objects.create(
        fuente=FocoIncendio.Fuente.NASA_FIRMS, ubicacion=Point(-75.35, 6.35, srid=4326),
        fecha_hora=datetime(2024, 7, 1, tzinfo=UTC), confianza="l",
    )
    FocoIncendio.objects.create(
        fuente=FocoIncendio.Fuente.INPE_QUEIMADAS, ubicacion=Point(-75.35, 6.35, srid=4326),
        fecha_hora=datetime(2024, 7, 1, tzinfo=UTC),
    )


@pytest.fixture
def pocas_celdas():
    with patch.object(modelo, "celdas_colombia", return_value=CELDAS):
        yield


@pytest.mark.django_db
def test_corrida_aprende_la_temporada_y_guarda_tres_meses(focos_cada_enero, pocas_celdas):
    rionegro = Municipio.objects.create(
        nombre="Rionegro", departamento="Antioquia", codigo_dane="05615",
        geom=MultiPolygon(Polygon(((-75.5, 6.0), (-75.5, 6.25), (-75.0, 6.25), (-75.0, 6.0), (-75.5, 6.0))), srid=4326),
    )
    corrida = ModeloRecurrencia(pd.Period("2025-11", "M")).ejecutar_corrida()

    zonas = pd.DataFrame(
        corrida.zonas.values(
            "area", "mes_objetivo", "puntaje_recurrencia", "municipio", "cantidad_incendios_historicos"
        )
    )
    assert len(zonas) == len(CELDAS) * 3
    assert sorted(zonas["mes_objetivo"].astype(str).unique()) == ["2025-12-01", "2026-01-01", "2026-02-01"]

    zonas["fuego"] = [round(a.centroid.y, 2) == 6.15 for a in zonas["area"]]
    enero = zonas[zonas["mes_objetivo"].astype(str) == "2026-01-01"]
    febrero = zonas[zonas["mes_objetivo"].astype(str) == "2026-02-01"]
    # En enero las celdas que siempre se queman puntúan más que las que nunca, y más que en febrero.
    assert enero[enero.fuego].puntaje_recurrencia.min() > enero[~enero.fuego].puntaje_recurrencia.max()
    assert enero[enero.fuego].puntaje_recurrencia.mean() > febrero[febrero.fuego].puntaje_recurrencia.mean()
    # 7 eneros con fuego (2019-2025); el ruido de baja confianza e INPE no cuenta.
    assert set(zonas[zonas.fuego].cantidad_incendios_historicos) == {7}
    assert set(zonas[~zonas.fuego].cantidad_incendios_historicos) == {0}
    # La fila y=61 cae en el polígono de Rionegro; la y=63 (6,35°) queda fuera.
    assert set(zonas[zonas.fuego].municipio) == {rionegro.pk}
    assert zonas[~zonas.fuego].municipio.isna().all()

    m = corrida.metricas
    assert m["prueba"] == "2024-12..2025-11" and m["validacion"] == "2023-12..2024-11"
    assert set(m["horizontes"]) == {"1", "2", "3"}
    assert set(m["horizontes"]["1"]["prueba"]) == {
        "persistencia", "recurrencia_estacional", "regresion_logistica", "gradient_boosting",
    }
    assert m["horizontes"]["1"]["prueba"]["gradient_boosting"]["auc"] == 1.0


@pytest.mark.django_db
def test_comando_y_tarea_crean_una_corrida(focos_cada_enero, pocas_celdas, capsys):
    call_command("entrenar_modelo_recurrencia", ultimo_mes="2025-11")
    assert "Horizonte 1" in capsys.readouterr().out

    from apps.prediccion.tasks import ejecutar_corrida

    # La tarea usa el mes pasado como último mes observado.
    assert CorridaModeloML.objects.filter(pk=ejecutar_corrida()).exists()
    assert CorridaModeloML.objects.count() == 2


def test_la_malla_cubre_colombia_y_nada_mas():
    celdas = set(modelo.celdas_colombia().itertuples(index=False, name=None))
    assert 9000 < len(celdas) < 10000  # ~9.300 celdas de 0,1° en el diseño D4
    assert (-754, 61) in celdas  # Rionegro
    assert (-670, 104) not in celdas  # Caracas
