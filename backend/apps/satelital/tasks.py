"""
Tareas de Celery de la app satelital — ver Vigia-UML-Secuencia § Detección
Satelital Automática y Vigia-UML-Despliegue § Celery Beat.
"""

import logging

from celery import shared_task
from django.db.models import Max

from apps.alertas.motor import MotorAlertas
from apps.satelital.clientes import ClienteInpeQueimadas, ClienteNasaFirms
from apps.satelital.models import FocoIncendio

logger = logging.getLogger(__name__)

# Fuentes en tiempo real, en el orden en que se consultan.
FUENTES_TIEMPO_REAL = (
    ("NASA_FIRMS", ClienteNasaFirms),
    ("INPE_QUEIMADAS", ClienteInpeQueimadas),
)


@shared_task
def sincronizar_focos() -> dict:
    """
    Sincroniza los focos de todas las fuentes satelitales en tiempo real.
    Una fuente caída no debe impedir que se consulten las demás, así que
    cada cliente falla de forma aislada: el resultado indica cuántos focos
    nuevos entraron por fuente, o `None` si esa fuente falló, y cuántas
    alertas generaron los focos nuevos.
    """
    # Los clientes insertan en lote sin decir qué filas son nuevas; el pk
    # serial sí lo dice.
    ultimo_pk = FocoIncendio.objects.aggregate(m=Max("pk"))["m"] or 0
    resultado = {}
    for nombre, clase in FUENTES_TIEMPO_REAL:
        try:
            resultado[nombre] = clase().sincronizar()
        except Exception:
            logger.exception("Falló la sincronización de %s", nombre)
            resultado[nombre] = None
    motor = MotorAlertas()
    resultado["alertas"] = sum(
        motor.evaluar_foco_nuevo(foco) is not None
        for foco in FocoIncendio.objects.filter(pk__gt=ultimo_pk).order_by("pk")
    )
    return resultado
