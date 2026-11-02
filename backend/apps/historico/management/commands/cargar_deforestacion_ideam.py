"""
Carga la deforestación anual del IDEAM por municipio (2018-2019 … 2024-2025).
Descarga cada raster (~50 MB) a un temporal y verifica su SHA-256; con
--directorio usa archivos ya descargados. Es seguro repetirlo. Requiere los
municipios (`cargar_municipios --ejecutar`).
"""

from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from apps.historico.ideam import CATALOGO, cargar_periodo


class Command(BaseCommand):
    help = "Carga la deforestación del IDEAM por municipio y año."

    def add_arguments(self, parser):
        parser.add_argument(
            "anios", nargs="*", type=int, help=f"Años finales del periodo (por defecto {sorted(CATALOGO)})."
        )
        parser.add_argument("--directorio", type=Path, help="Carpeta con los .img ya descargados.")

    def handle(self, *args, anios=None, directorio=None, **opciones):
        anios = anios or sorted(CATALOGO)
        directorio = Path(directorio) if directorio else None  # call_command no aplica `type`
        if desconocidos := set(anios) - set(CATALOGO):
            raise CommandError(f"Sin raster en el catálogo para {sorted(desconocidos)}.")
        for anio in anios:
            r = cargar_periodo(anio, directorio)
            self.stdout.write(
                f"{anio - 1}–{anio}: {r['hectareas']:,.0f} ha en {r['municipios']} municipios "
                f"({r['hectareas_sin_municipio']:,.0f} ha sin municipio)."
            )
