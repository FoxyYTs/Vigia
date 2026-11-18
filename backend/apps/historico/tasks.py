from celery import shared_task

from apps.historico.clientes import ClienteUngrd


@shared_task
def sincronizar_ungrd() -> int:
    """Incendios reportados a la UNGRD nuevos (idempotente). La lanza el staff
    desde "Gestionar Históricos"."""
    return ClienteUngrd().sincronizar()
