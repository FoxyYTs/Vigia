"""
Entrena el modelo de recurrencia, imprime sus métricas contra las bases y
guarda las zonas de los 3 meses siguientes (lo mismo que hace Celery Beat cada
mes). Con --ultimo-mes AAAA-MM se fija el último mes observado.
"""

import pandas as pd
from django.core.management.base import BaseCommand

from apps.prediccion.modelo import ModeloRecurrencia


class Command(BaseCommand):
    help = "Entrena el modelo de recurrencia y guarda una corrida con sus zonas."

    def add_arguments(self, parser):
        parser.add_argument("--ultimo-mes", help="Último mes observado (AAAA-MM). Por defecto, el mes pasado.")

    def handle(self, *args, ultimo_mes=None, **opciones):
        modelo = ModeloRecurrencia(pd.Period(ultimo_mes, "M") if ultimo_mes else None)
        corrida = modelo.ejecutar_corrida()
        m = corrida.metricas
        self.stdout.write(
            f"Corrida #{corrida.pk}: {m['celdas']} celdas, prevalencia {m['prevalencia']}, "
            f"validación {m['validacion']}, prueba {m['prueba']}."
        )
        for h, tramos in m["horizontes"].items():
            self.stdout.write(f"Horizonte {h} mes(es) — prueba:")
            for modelo_nombre, valores in tramos["prueba"].items():
                self.stdout.write(f"  {modelo_nombre:24} {valores}")
        self.stdout.write(self.style.SUCCESS(f"{corrida.zonas.count()} zonas guardadas."))
