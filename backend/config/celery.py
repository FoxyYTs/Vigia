"""
Configuración de Celery — Worker y Beat.

Ver Vigia-UML-Despliegue (vault de Obsidian): Celery Worker es el único
componente que habla con servicios externos (FIRMS, INPE, IDEAM, UNGRD,
FCM, Telegram); Celery Beat solo programa tareas, no las ejecuta.

Cronograma real de `beat_schedule` se agrega cuando existan las tareas de
`apps.satelital` / `apps.historico` / `apps.prediccion` (objetivo
específico 3 — implementación).
"""

import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.local")

app = Celery("vigia")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

# Ejemplo de lo que va aquí una vez existan las tareas (ver
# Vigia-UML-Despliegue § Celery Beat "scheduler cada 3h"):
#
# app.conf.beat_schedule = {
#     "sincronizar-focos-satelitales": {
#         "task": "apps.satelital.tasks.sincronizar_focos",
#         "schedule": crontab(minute=0, hour="*/3"),
#     },
# }
