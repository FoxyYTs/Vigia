"""Tareas de Celery de predicción — reentrenamiento mensual del modelo de recurrencia."""

from celery import shared_task

from apps.prediccion.modelo import ModeloRecurrencia


@shared_task
def ejecutar_corrida() -> int:
    """Reentrena con el histórico hasta el último mes completo y guarda las
    zonas de los 3 meses siguientes. Retorna el id de la corrida."""
    return ModeloRecurrencia().ejecutar_corrida().pk
