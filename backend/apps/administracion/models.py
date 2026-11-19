"""
Sin modelos a propósito: las estadísticas (estadisticas.py) y los informes
(exportador.py, ExportadorDatos) se calculan al vuelo y no persisten nada —
ver Vigia-Modelo-Datos § Decisiones.
"""

from django.contrib.gis.db import models  # noqa: F401  (PostGIS)
