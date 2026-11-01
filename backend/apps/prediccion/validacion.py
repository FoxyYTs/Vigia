"""
Validación del modelo de recurrencia contra los incendios forestales
reportados a la UNGRD — ver Vigia-Plan-I1c-Historicos § Fase 2 (vault).

El modelo aprende de detecciones satelitales (FIRMS), que incluyen quemas
agrícolas. Aquí se mide si, cuando el modelo marca un municipio como
riesgoso, hubo incendios reportados en terreno.

Backtest: se entrena con 2020–2022 y se predice cada mes de 2023–2024 con la
misma estrategia directa (variables ≤ t−h). La UNGRD no tiene datos después
de 2024, por eso no se usa la corrida mensual de producción.
"""

import numpy as np
import pandas as pd
from django.db import connection

from apps.historico.models import IncendioReportado
from apps.prediccion.modelo import (
    HORIZONTES,
    INICIO,
    INICIO_ENTRENAMIENTO,
    CELDA,
    _clasificador,
    _metricas,
    celdas_colombia,
    construir_panel,
    focos_por_celda_mes,
    variables,
)
from apps.usuarios.models import Municipio

FIN_ENTRENAMIENTO = pd.Period("2022-12", "M")
EVALUACION = (pd.Period("2023-01", "M"), pd.Period("2024-12", "M"))


def celdas_por_municipio(celdas: pd.DataFrame) -> pd.DataFrame:
    """Pares (c, municipio) de cada celda con los municipios que toca. Se usa
    la intersección y no el centro de la celda: con el centro, los municipios
    andinos más pequeños que una celda (~11 km) quedarían sin ninguna."""
    sql = f"""
        SELECT c.i, m.id
        FROM unnest(%s::int[], %s::int[], %s::int[]) AS c(i, x, y)
        JOIN {Municipio._meta.db_table} m ON m.geom IS NOT NULL AND ST_Intersects(
            m.geom, ST_MakeEnvelope(c.x * %s, c.y * %s, (c.x + 1) * %s, (c.y + 1) * %s, 4326)
        )
    """
    with connection.cursor() as cursor:
        cursor.execute(
            sql,
            [list(range(len(celdas))), celdas["x"].tolist(), celdas["y"].tolist(), CELDA, CELDA, CELDA, CELDA],
        )
        return pd.DataFrame(cursor.fetchall(), columns=["c", "municipio"])


def incendios_por_municipio_mes(desde: pd.Period, hasta: pd.Period) -> pd.DataFrame:
    """Municipio-mes con al menos un incendio forestal reportado a la UNGRD."""
    filas = IncendioReportado.objects.filter(
        municipio__isnull=False, fecha__gte=desde.start_time.date(), fecha__lte=hasta.end_time.date()
    ).values_list("municipio", "fecha")
    df = pd.DataFrame(list(filas), columns=["municipio", "fecha"])
    df["p"] = pd.PeriodIndex(pd.to_datetime(df["fecha"]), freq="M")
    return df[["municipio", "p"]].drop_duplicates()


def agregar_por_municipio(celda_mes: pd.DataFrame, pares: pd.DataFrame) -> pd.DataFrame:
    """De celdas a municipios. `celda_mes` trae c, p, puntaje, base y fuego.
    Puntaje del municipio = 1 − ∏(1 − p): probabilidad de al menos una
    detección en sus celdas si fueran independientes. El máximo favorecería
    a los municipios grandes de forma distinta a como lo hace la realidad."""
    df = celda_mes.merge(pares, on="c")
    for col in ("puntaje", "base"):
        df[f"log_{col}"] = np.log1p(-df[col].clip(0, 1 - 1e-9))
    agg = df.groupby(["municipio", "p"]).agg(
        log_puntaje=("log_puntaje", "sum"), log_base=("log_base", "sum"), firms=("fuego", "max")
    )
    return pd.DataFrame({
        "puntaje": 1 - np.exp(agg["log_puntaje"]),
        "base": 1 - np.exp(agg["log_base"]),
        "firms": agg["firms"].astype(int),
    }).reset_index()


def _comparar(df: pd.DataFrame) -> dict:
    y = df["ungrd"].to_numpy()
    return {
        "municipio_mes": int(len(df)),
        "prevalencia_ungrd": round(float(y.mean()), 4) if len(y) else None,
        "gradient_boosting": _metricas(y, df["puntaje"].to_numpy()),
        "recurrencia_estacional": _metricas(y, df["base"].to_numpy()),
    }


def _concordancia(df: pd.DataFrame) -> dict:
    firms, ungrd = df["firms"].astype(bool), df["ungrd"].astype(bool)
    ambos = int((firms & ungrd).sum())
    return {
        "firms_y_ungrd": ambos,
        "solo_firms": int((firms & ~ungrd).sum()),
        "solo_ungrd": int((~firms & ungrd).sum()),
        "ninguno": int((~firms & ~ungrd).sum()),
        # De los municipio-mes con incendio reportado, ¿cuántos vio el satélite?
        "ungrd_con_deteccion": round(float(ambos / ungrd.sum()), 4) if ungrd.sum() else None,
        # De los municipio-mes con detección, ¿cuántos tuvieron un reporte?
        "firms_con_reporte": round(float(ambos / firms.sum()), 4) if firms.sum() else None,
    }


def validar(fin_entrenamiento: pd.Period = FIN_ENTRENAMIENTO, evaluacion=EVALUACION) -> dict:
    desde, hasta = evaluacion
    celdas = celdas_colombia()
    meses = pd.period_range(INICIO, hasta, freq="M")
    panel = construir_panel(celdas, focos_por_celda_mes(INICIO, hasta), meses, hasta)
    pares = celdas_por_municipio(celdas)
    reportes = incendios_por_municipio_mes(desde, hasta).assign(ungrd=1)
    # Municipios que reportaron a la UNGRD antes de la evaluación: los demás
    # pueden tener incendios que nunca se reportaron.
    reportan = set(incendios_por_municipio_mes(INICIO, desde - 1)["municipio"])

    entrena = (panel["p"] >= INICIO_ENTRENAMIENTO) & (panel["p"] <= fin_entrenamiento)
    evalua = (panel["p"] >= desde) & (panel["p"] <= hasta)
    resultado = {
        "entrenamiento": f"{INICIO_ENTRENAMIENTO}..{fin_entrenamiento}",
        "evaluacion": f"{desde}..{hasta}",
        "municipios": int(pares["municipio"].nunique()),
        "municipios_que_reportan": len(reportan),
        "horizontes": {},
    }
    for h in HORIZONTES:
        X = variables(panel, h)
        modelo = _clasificador().fit(X[entrena], panel.loc[entrena, "fuego"])
        celda_mes = panel.loc[evalua, ["c", "p", "fuego"]].assign(
            puntaje=modelo.predict_proba(X[evalua])[:, 1], base=X.loc[evalua, "fm_prev"].to_numpy()
        )
        mm = agregar_por_municipio(celda_mes, pares).merge(reportes, on=["municipio", "p"], how="left")
        mm["ungrd"] = mm["ungrd"].fillna(0).astype(int)
        resultado["horizontes"][str(h)] = {
            "todos": _comparar(mm),
            "solo_municipios_que_reportan": _comparar(mm[mm["municipio"].isin(reportan)]),
        }
        if h == HORIZONTES[0]:
            resultado["concordancia_firms_ungrd"] = _concordancia(mm)
    return resultado
