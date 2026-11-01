"""
Carga los incendios forestales reportados a la UNGRD (2019–2024). Es seguro
repetirlo: solo agrega los que faltan. Requiere los municipios cargados
(`cargar_municipios --ejecutar`) para asignar cada incendio a su municipio.
"""

from django.core.management.base import BaseCommand
from django.db.models import Count

from apps.historico.clientes import ClienteUngrd
from apps.historico.models import IncendioReportado


class Command(BaseCommand):
    help = "Carga los incendios forestales reportados a la UNGRD (datos.gov.co)."

    def handle(self, *args, **opciones):
        nuevos = ClienteUngrd().sincronizar()
        total = IncendioReportado.objects.count()
        sin_municipio = IncendioReportado.objects.filter(municipio=None).count()
        self.stdout.write(f"Nuevos: {nuevos}. Total: {total}. Sin municipio: {sin_municipio}.")
        for fila in IncendioReportado.objects.values("fecha__year").annotate(n=Count("id")).order_by("fecha__year"):
            self.stdout.write(f"  {fila['fecha__year']}: {fila['n']}")
