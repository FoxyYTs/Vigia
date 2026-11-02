"""Retención de las fotos de los reportes — decisión del 30-sep-2026 (Ley 1581
de 2012, Habeas Data): la foto completa solo se guarda el tiempo necesario y
después queda la miniatura."""

from datetime import timedelta

from celery import shared_task
from django.db.models import Q
from django.utils import timezone

from apps.reportes.models import ReporteCiudadano

RETENCION = {
    ReporteCiudadano.Estado.RECHAZADO: timedelta(days=7),
    ReporteCiudadano.Estado.PENDIENTE: timedelta(days=30),
    ReporteCiudadano.Estado.VALIDADO: timedelta(days=90),
}


@shared_task
def purgar_fotos_reportes() -> int:
    """Borra la foto completa de los reportes que superaron su plazo (contado
    desde la creación) y conserva la miniatura. Retorna cuántas borró."""
    ahora = timezone.now()
    vencidos = ReporteCiudadano.objects.exclude(foto="").exclude(foto=None).filter(
        Q(estado=ReporteCiudadano.Estado.RECHAZADO, fecha_creacion__lt=ahora - RETENCION["rechazado"])
        | Q(estado=ReporteCiudadano.Estado.PENDIENTE, fecha_creacion__lt=ahora - RETENCION["pendiente"])
        | Q(estado=ReporteCiudadano.Estado.VALIDADO, fecha_creacion__lt=ahora - RETENCION["validado"])
    )
    borradas = 0
    for reporte in vencidos:
        reporte.foto.delete(save=False)  # borra el archivo del disco
        reporte.foto = None
        reporte.save(update_fields=["foto"])
        borradas += 1
    return borradas
