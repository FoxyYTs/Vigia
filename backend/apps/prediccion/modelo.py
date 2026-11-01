"""
ModeloRecurrencia — ver Vigia-Modelo-Recurrencia (diseño D4) y
Vigia-Plan-I2-Modelo (vault de Obsidian).

Clasificación binaria por celda de 0,1° (~11 km) y mes: ¿habrá al menos una
detección VIIRS (confianza ≠ 'l') en esa celda ese mes? La etiqueta no es
"incendio confirmado": incluye quemas agrícolas.

Horizonte de 3 meses con estrategia directa: un modelo por horizonte h, cuyas
variables solo ven información de h o más meses antes del mes objetivo. Así
no se predicen meses intermedios ni se filtra información del futuro.
"""

from datetime import date

import numpy as np
import pandas as pd
from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from django.db import connection, transaction
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from apps.prediccion.models import CorridaModeloML, ZonaRecurrente
from apps.satelital.geografia import contorno_colombia
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

VERSION = "recurrencia-hgb-1"
CELDA = 0.1  # grados
HORIZONTES = (1, 2, 3)
INICIO = pd.Period("2019-01", "M")  # 2019 solo calienta los rezagos
INICIO_ENTRENAMIENTO = pd.Period("2020-01", "M")
MESES_EVALUACION = 12  # prueba = últimos 12 meses; validación = los 12 anteriores
FRACCION_TOP = 0.05
VARIABLES = [
    "rec1", "rec2", "lag12", "ult3", "ult12", "fm_prev", "fm_cnt", "frp_prev",
    "vec_rec1", "mes_sin", "mes_cos", "lat", "lon",
]


def celdas_colombia() -> pd.DataFrame:
    """Celdas (x, y) — índices enteros de la malla — cuyo centro cae en Colombia."""
    contorno = contorno_colombia()
    preparado = contorno.prepared
    xmin, ymin, xmax, ymax = contorno.extent
    celdas = [
        (x, y)
        for x in range(int(np.floor(xmin / CELDA)), int(np.ceil(xmax / CELDA)))
        for y in range(int(np.floor(ymin / CELDA)), int(np.ceil(ymax / CELDA)))
        if preparado.contains(Point((x + 0.5) * CELDA, (y + 0.5) * CELDA, srid=4326))
    ]
    return pd.DataFrame(celdas, columns=["x", "y"])


def focos_por_celda_mes(desde: pd.Period, hasta: pd.Period) -> pd.DataFrame:
    """Detecciones NASA FIRMS (sin confianza baja) agregadas por celda y mes,
    meses [desde, hasta]. Columnas: x, y, p (Period), n, frp."""
    sql = f"""
        SELECT floor(ST_X(ubicacion::geometry) / %s)::int AS x,
               floor(ST_Y(ubicacion::geometry) / %s)::int AS y,
               date_trunc('month', fecha_hora AT TIME ZONE 'UTC')::date AS mes,
               count(*) AS n, sum(coalesce(brillo_frp, 0)) AS frp
        FROM {FocoIncendio._meta.db_table}
        WHERE fuente = %s AND confianza <> 'l' AND fecha_hora >= %s AND fecha_hora < %s
        GROUP BY 1, 2, 3
    """
    params = [
        CELDA, CELDA, FocoIncendio.Fuente.NASA_FIRMS,
        desde.start_time.tz_localize("UTC"), (hasta + 1).start_time.tz_localize("UTC"),
    ]
    with connection.cursor() as cursor:
        cursor.execute(sql, params)
        filas = cursor.fetchall()
    focos = pd.DataFrame(filas, columns=["x", "y", "mes", "n", "frp"])
    focos["p"] = pd.PeriodIndex(pd.to_datetime(focos["mes"]), freq="M")
    return focos.drop(columns="mes")


def construir_panel(
    celdas: pd.DataFrame, focos: pd.DataFrame, meses: pd.PeriodIndex, ultimo_observado: pd.Period
) -> pd.DataFrame:
    """Una fila por celda y mes. `fuego` es NaN después de `ultimo_observado`
    (los meses futuros que se van a predecir)."""
    idx = pd.MultiIndex.from_product([range(len(celdas)), meses], names=["c", "p"])
    panel = pd.DataFrame(index=idx).reset_index()
    panel["x"] = celdas["x"].to_numpy()[panel["c"]]
    panel["y"] = celdas["y"].to_numpy()[panel["c"]]
    panel = panel.merge(focos[["x", "y", "p", "n", "frp"]], on=["x", "y", "p"], how="left")
    panel[["n", "frp"]] = panel[["n", "frp"]].fillna(0)
    panel["fuego"] = np.where(panel["p"] <= ultimo_observado, (panel["n"] > 0).astype(float), np.nan)
    panel["t"] = panel["p"].dt.year * 12 + panel["p"].dt.month
    panel["mes_n"] = panel["p"].dt.month
    return panel.sort_values(["c", "t"]).reset_index(drop=True)


def variables(panel: pd.DataFrame, h: int) -> pd.DataFrame:
    """Las 13 variables del diseño D4 para predecir con `h` meses de
    anticipación: solo usan `fuego`/`frp` de los meses t-h o anteriores."""
    v = pd.DataFrame(index=panel.index)
    g = panel.groupby("c")
    fuego = g["fuego"]
    v["rec1"] = fuego.shift(h)
    v["rec2"] = fuego.shift(h + 1)
    v["lag12"] = fuego.shift(12)
    v["ult3"] = fuego.transform(lambda s: s.shift(h).rolling(3, min_periods=1).sum())
    v["ult12"] = fuego.transform(lambda s: s.shift(h).rolling(12, min_periods=1).sum())
    # Mismo mes calendario en años anteriores: siempre ≥ 12 meses atrás (> h).
    por_mes = panel.groupby(["c", "mes_n"])["fuego"]
    v["fm_prev"] = por_mes.transform(lambda s: s.shift(1).expanding().mean())
    v["fm_cnt"] = panel.groupby(["c", "mes_n"]).cumcount()
    v["frp_prev"] = g["frp"].transform(lambda s: s.shift(h).rolling(12, min_periods=1).mean())
    v["vec_rec1"] = _vecinos(panel, h)
    v["mes_sin"] = np.sin(2 * np.pi * panel["mes_n"] / 12)
    v["mes_cos"] = np.cos(2 * np.pi * panel["mes_n"] / 12)
    v["lat"] = (panel["y"] + 0.5) * CELDA
    v["lon"] = (panel["x"] + 0.5) * CELDA
    return v[VARIABLES].fillna(0)


def _vecinos(panel: pd.DataFrame, h: int) -> np.ndarray:
    """Cuántas de las 8 celdas vecinas tuvieron fuego en el mes t-h."""
    clave = panel.set_index(["x", "y", "t"])["fuego"]
    total = np.zeros(len(panel))
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx or dy:
                k = pd.MultiIndex.from_arrays([panel["x"] + dx, panel["y"] + dy, panel["t"] - h])
                total += clave.reindex(k).fillna(0).to_numpy()
    return total


def _precision_top(y: np.ndarray, puntaje: np.ndarray) -> float:
    n = max(1, int(len(y) * FRACCION_TOP))
    return float(y[np.argsort(-puntaje)[:n]].mean())


def _metricas(y: np.ndarray, puntaje: np.ndarray) -> dict:
    if len(np.unique(y)) < 2:  # sin positivos o sin negativos no hay AUC
        return {"auc": None, "pr_auc": None, "precision_top5": None}
    return {
        "auc": round(float(roc_auc_score(y, puntaje)), 4),
        "pr_auc": round(float(average_precision_score(y, puntaje)), 4),
        "precision_top5": round(_precision_top(y, puntaje), 4),
    }


def _clasificador():
    return HistGradientBoostingClassifier(max_iter=200, learning_rate=0.08, random_state=0)


class ModeloRecurrencia:
    def __init__(self, ultimo_mes: pd.Period | None = None):
        # Último mes completo observado (el actual va a medias).
        self.ultimo_mes = ultimo_mes or pd.Period(date.today(), "M") - 1
        self.metricas: dict = {}
        self._modelos: dict = {}
        self._panel: pd.DataFrame | None = None
        self._celdas: pd.DataFrame | None = None

    def _cargar(self):
        self._celdas = celdas_colombia()
        meses = pd.period_range(INICIO, self.ultimo_mes + max(HORIZONTES), freq="M")
        focos = focos_por_celda_mes(INICIO, self.ultimo_mes)
        self._panel = construir_panel(self._celdas, focos, meses, self.ultimo_mes)

    def entrenar(self) -> dict:
        """Evalúa cada horizonte con validación temporal contra las bases y
        deja entrenado el modelo final con todos los meses observados."""
        if self._panel is None:
            self._cargar()
        panel = self._panel
        prueba_desde = self.ultimo_mes - MESES_EVALUACION + 1
        valid_desde = prueba_desde - MESES_EVALUACION
        observados = (panel["p"] >= INICIO_ENTRENAMIENTO) & (panel["p"] <= self.ultimo_mes)
        self.metricas = {
            "ultimo_mes_observado": str(self.ultimo_mes),
            "validacion": f"{valid_desde}..{prueba_desde - 1}",
            "prueba": f"{prueba_desde}..{self.ultimo_mes}",
            "celdas": int(len(self._celdas)),
            "prevalencia": round(float(panel.loc[observados, "fuego"].mean()), 4),
            "horizontes": {},
        }
        for h in HORIZONTES:
            X = variables(panel, h)
            y = panel["fuego"]
            tramos = {
                "entrenamiento": observados & (panel["p"] < valid_desde),
                "validacion": (panel["p"] >= valid_desde) & (panel["p"] < prueba_desde),
                "prueba": (panel["p"] >= prueba_desde) & (panel["p"] <= self.ultimo_mes),
            }
            ent = tramos["entrenamiento"]
            hgb = _clasificador().fit(X[ent], y[ent])
            logistica = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000)).fit(X[ent], y[ent])
            resultado = {}
            for nombre in ("validacion", "prueba"):
                m = tramos[nombre]
                yv = y[m].to_numpy()
                resultado[nombre] = {
                    "persistencia": _metricas(yv, X.loc[m, "rec1"].to_numpy()),
                    "recurrencia_estacional": _metricas(yv, X.loc[m, "fm_prev"].to_numpy()),
                    "regresion_logistica": _metricas(yv, logistica.predict_proba(X[m])[:, 1]),
                    "gradient_boosting": _metricas(yv, hgb.predict_proba(X[m])[:, 1]),
                }
            self.metricas["horizontes"][str(h)] = resultado
            self._modelos[h] = _clasificador().fit(X[observados], y[observados])
        return self.metricas

    def predecir_zonas(self) -> pd.DataFrame:
        """Probabilidad por celda para los meses ultimo_mes+1 … +3.
        Columnas: x, y, mes_objetivo (Period), puntaje, meses_con_fuego."""
        if not self._modelos:
            self.entrenar()
        panel = self._panel
        meses_con_fuego = panel[panel["p"] <= self.ultimo_mes].groupby("c")["fuego"].sum()
        partes = []
        for h, modelo in self._modelos.items():
            objetivo = self.ultimo_mes + h
            m = panel["p"] == objetivo
            parte = panel.loc[m, ["c", "x", "y"]].copy()
            parte["mes_objetivo"] = objetivo
            parte["puntaje"] = modelo.predict_proba(variables(panel, h)[m])[:, 1]
            parte["meses_con_fuego"] = meses_con_fuego.reindex(parte["c"]).fillna(0).astype(int).to_numpy()
            partes.append(parte.drop(columns="c"))
        return pd.concat(partes, ignore_index=True)

    @transaction.atomic
    def ejecutar_corrida(self) -> CorridaModeloML:
        zonas = self.predecir_zonas()
        corrida = CorridaModeloML.objects.create(
            version_modelo=VERSION,
            metricas=self.metricas,
            notas=f"Horizontes {list(HORIZONTES)} desde {self.ultimo_mes}.",
        )
        ZonaRecurrente.objects.bulk_create(
            [
                ZonaRecurrente(
                    corrida=corrida,
                    area=_cuadro(z.x, z.y),
                    mes_objetivo=z.mes_objetivo.start_time.date(),
                    puntaje_recurrencia=round(float(z.puntaje), 4),
                    cantidad_incendios_historicos=int(z.meses_con_fuego),
                )
                for z in zonas.itertuples()
            ],
            batch_size=5000,
        )
        with connection.cursor() as cursor:
            # Municipio de cada zona: el que contiene el centro de la celda.
            cursor.execute(
                f"""
                UPDATE {ZonaRecurrente._meta.db_table} z SET municipio_id = m.id
                FROM {Municipio._meta.db_table} m
                WHERE z.corrida_id = %s AND m.geom IS NOT NULL
                  AND ST_Contains(m.geom, ST_Centroid(z.area))
                """,
                [corrida.pk],
            )
        return corrida


def _cuadro(x: int, y: int) -> MultiPolygon:
    x0, y0 = round(x * CELDA, 4), round(y * CELDA, 4)
    x1, y1 = round(x0 + CELDA, 4), round(y0 + CELDA, 4)
    return MultiPolygon(Polygon(((x0, y0), (x0, y1), (x1, y1), (x1, y0), (x0, y0))), srid=4326)
