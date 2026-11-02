"""
Elimina de la base los focos de NASA FIRMS que caen fuera de Colombia (el
histórico se cargó con un rectángulo que incluye países vecinos y mar).

Sin argumentos solo cuenta (simulacro). Para borrar de verdad: --ejecutar.
Es seguro repetirlo, y los datos borrados se pueden volver a descargar con
`cargar_historico_firms` (que ya filtra al ingerir).
"""

from django.core.management.base import BaseCommand
from django.db import connection

from apps.satelital.geografia import contorno_colombia
from apps.satelital.models import FocoIncendio

FUERA = "fuente = %s AND NOT ST_Intersects(ubicacion::geometry, ST_GeomFromEWKB(%s))"


class Command(BaseCommand):
    help = "Elimina los focos de NASA FIRMS fuera de Colombia (simulacro salvo --ejecutar)."

    def add_arguments(self, parser):
        parser.add_argument("--ejecutar", action="store_true", help="Borra de verdad.")

    def handle(self, *args, ejecutar=False, **opciones):
        params = [FocoIncendio.Fuente.NASA_FIRMS, contorno_colombia().ewkb]
        with connection.cursor() as cursor:
            cursor.execute("SELECT count(*) FROM satelital_focoincendio")
            total = cursor.fetchone()[0]
            cursor.execute(f"SELECT count(*) FROM satelital_focoincendio WHERE {FUERA}", params)
            fuera = cursor.fetchone()[0]
            self.stdout.write(f"Focos totales: {total}. Fuera de Colombia (NASA FIRMS): {fuera}.")
            if not ejecutar:
                self.stdout.write("Simulacro: no se borró nada. Usar --ejecutar para eliminarlos.")
                return
            cursor.execute(f"DELETE FROM satelital_focoincendio WHERE {FUERA}", params)
            self.stdout.write(self.style.SUCCESS(f"Eliminados: {cursor.rowcount}."))
