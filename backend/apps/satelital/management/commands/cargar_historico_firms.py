"""
Carga masiva del histórico de focos de NASA FIRMS.

Ejemplos:
    python manage.py cargar_historico_firms                       # 2018-04-01 → 2026-06-30
    python manage.py cargar_historico_firms --sensor VIIRS_NOAA20_NRT \\
        --desde 2026-07-01 --hasta 2026-09-23                     # empalme con tiempo real

Es idempotente: los focos ya existentes se ignoran, así que se puede
reanudar tras un corte volviendo a ejecutarlo.
"""

from datetime import date

from django.core.management.base import BaseCommand, CommandError

from apps.satelital.clientes import ClienteNasaFirms


def _fecha(valor: str) -> date:
    try:
        return date.fromisoformat(valor)
    except ValueError as e:
        raise CommandError(f"Fecha inválida '{valor}', usar AAAA-MM-DD.") from e


class Command(BaseCommand):
    help = "Carga el histórico de focos de NASA FIRMS (ventanas de 5 días, idempotente)."

    def add_arguments(self, parser):
        parser.add_argument("--desde", default="2018-04-01", help="Por defecto, inicio de VIIRS_NOAA20_SP.")
        parser.add_argument("--hasta", default="2026-06-30", help="Por defecto, fin de VIIRS_NOAA20_SP.")
        parser.add_argument("--sensor", default=None, help="Por defecto, VIIRS_NOAA20_SP.")

    def handle(self, *args, **opciones):
        desde, hasta = _fecha(opciones["desde"]), _fecha(opciones["hasta"])
        if hasta < desde:
            raise CommandError("--hasta no puede ser anterior a --desde.")
        cliente = ClienteNasaFirms()
        sensor = opciones["sensor"] or cliente.SENSOR_HISTORICO
        self.stdout.write(f"Descargando {sensor} de {desde} a {hasta}...")
        nuevos = cliente.descargar_historico(desde, hasta, sensor=sensor)
        self.stdout.write(self.style.SUCCESS(f"Listo: {nuevos} focos nuevos."))
