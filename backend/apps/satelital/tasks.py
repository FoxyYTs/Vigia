"""
Tareas de Celery de la app satelital — ver Vigia-UML-Secuencia § Detección
Satelital Automática y Vigia-UML-Despliegue § Celery Beat.
"""

import logging

from celery import shared_task

from apps.satelital.clientes import ClienteInpeQueimadas, ClienteNasaFirms

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
    nuevos entraron por fuente, o `None` si esa fuente falló.
    """
    resultado = {}
    for nombre, clase in FUENTES_TIEMPO_REAL:
        try:
            resultado[nombre] = clase().sincronizar()
        except Exception:
            logger.exception("Falló la sincronización de %s", nombre)
            resultado[nombre] = None
    return resultado
