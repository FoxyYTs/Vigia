"""
ExportadorDatos (sin persistencia, generación al vuelo) + estadísticas del panel admin — ver Vigia-Modelo-Datos § Decisiones

Estructura de repo — pendiente de implementación (objetivo específico 3).
No agregar campos aquí sin revisar primero la nota correspondiente en el
vault de Obsidian; el modelo de datos ya está cerrado y validado ahí.
"""

from django.contrib.gis.db import models  # noqa: F401  (PostGIS)
