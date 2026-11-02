"""
Configuración de Celery — Worker y Beat.

Ver Vigia-UML-Despliegue (vault de Obsidian): Celery Worker es el único
componente que habla con servicios externos (FIRMS, INPE, IDEAM, UNGRD,
FCM, Telegram); Celery Beat solo programa tareas, no las ejecuta.

`beat_schedule` se va ampliando a medida que existen las tareas de
`apps.historico` / `apps.prediccion` (objetivo específico 3).
"""

import os

from celery import Celery
from celery.schedules import crontab

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.local")

app = Celery("vigia")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

# Con `DatabaseScheduler` (ver docker-compose) Beat copia este cronograma a la
# base de datos al arrancar.
app.conf.beat_schedule = {
    "sincronizar-focos-satelitales": {
        "task": "apps.satelital.tasks.sincronizar_focos",
        "schedule": crontab(minute=0, hour="*/3"),
    },
    # Día 2: el mes anterior ya está completo y la ingesta del día 1 terminó.
    # Retención de fotos de reportes (Ley 1581): a diario, de madrugada.
    "purgar-fotos-reportes": {
        "task": "apps.reportes.tasks.purgar_fotos_reportes",
        "schedule": crontab(minute=30, hour=3),
    },
    "reentrenar-modelo-recurrencia": {
        "task": "apps.prediccion.tasks.ejecutar_corrida",
        "schedule": crontab(minute=0, hour=4, day_of_month=2),
    },
}
