"""
Backtest del modelo de recurrencia contra los incendios reportados a la
UNGRD: entrena con 2020–2022 y evalúa 2023–2024 por municipio y mes. Requiere
los municipios (`cargar_municipios`) y los incendios (`cargar_incendios_ungrd`).
"""

import json
from pathlib import Path

from django.core.management.base import BaseCommand

from apps.prediccion.validacion import validar


class Command(BaseCommand):
    help = "Valida el modelo de recurrencia contra los incendios reportados a la UNGRD."

    def add_arguments(self, parser):
        parser.add_argument("--salida", help="Archivo JSON donde guardar el resultado completo.")

    def handle(self, *args, salida=None, **opciones):
        r = validar()
        self.stdout.write(
            f"Entrenamiento {r['entrenamiento']}, evaluación {r['evaluacion']}: "
            f"{r['municipios']} municipios ({r['municipios_que_reportan']} reportaron antes)."
        )
        for h, grupos in r["horizontes"].items():
            for grupo, m in grupos.items():
                self.stdout.write(f"Horizonte {h} · {grupo} ({m['municipio_mes']} municipio-mes, "
                                  f"prevalencia {m['prevalencia_ungrd']}):")
                self.stdout.write(f"  gradient boosting       {m['gradient_boosting']}")
                self.stdout.write(f"  recurrencia estacional  {m['recurrencia_estacional']}")
        self.stdout.write(f"Concordancia FIRMS ↔ UNGRD: {r['concordancia_firms_ungrd']}")
        if salida:
            Path(salida).write_text(json.dumps(r, indent=1, ensure_ascii=False))
            self.stdout.write(self.style.SUCCESS(f"Guardado en {salida}"))
