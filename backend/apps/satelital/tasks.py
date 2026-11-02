"""
Tareas de Celery de la app satelital — ver Vigia-UML-Secuencia § Detección
Satelital Automática y Vigia-UML-Despliegue § Celery Beat.
"""

import logging
from datetime import timedelta

from celery import shared_task
from django.db.models import Max
from django.utils import timezone

from apps.alertas.motor import MotorAlertas
from apps.satelital.clientes import ClienteInpeQueimadas, ClienteNasaFirms
from apps.satelital.models import FocoIncendio

logger = logging.getLogger(__name__)

# Fuentes en tiempo real, en el orden en que se consultan.
FUENTES_TIEMPO_REAL = (
    ("NASA_FIRMS", ClienteNasaFirms),
    ("INPE_QUEIMADAS", ClienteInpeQueimadas),
)

# Tras una caída se recuperan los días perdidos, hasta este límite.
MAX_DIAS_RECUPERACION = 30
# Los focos recuperados de días atrás se guardan, pero no disparan alertas.
ANTIGUEDAD_MAXIMA_ALERTA = timedelta(hours=24)


def dias_a_sincronizar(fuente: str) -> int:
    """Días desde el último foco de la fuente (1 si es reciente o no hay)."""
    ultimo = FocoIncendio.objects.filter(fuente=fuente).aggregate(m=Max("fecha_hora"))["m"]
    if ultimo is None:
        return 1
    return min(MAX_DIAS_RECUPERACION, (timezone.now() - ultimo).days + 1)


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
            resultado[nombre] = clase().sincronizar(dias=dias_a_sincronizar(clase.FUENTE))
        except Exception:
            logger.exception("Falló la sincronización de %s", nombre)
            resultado[nombre] = None
    motor = MotorAlertas()
    resultado["alertas"] = sum(
        motor.evaluar_foco_nuevo(foco) is not None
        for foco in FocoIncendio.objects.filter(
            pk__gt=ultimo_pk, fecha_hora__gte=timezone.now() - ANTIGUEDAD_MAXIMA_ALERTA
        ).order_by("pk")
    )
    return resultado
