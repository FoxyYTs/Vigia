"""
Carga los municipios con código DANE y polígono (data/municipios.geojson) y
la jurisdicción de las CAR (data/entidades.json). Ver data/LICENCIA.md.

Sin argumentos es un simulacro: cuenta lo que haría y no guarda nada. Para
aplicar: --ejecutar. Es seguro repetirlo.

Las filas creadas a mano antes (sin código, p. ej. "Rionegro, Antioquia") se
completan en vez de duplicarse: se buscan por nombre y departamento.
"""

import json
from pathlib import Path

from django.contrib.gis.geos import GEOSGeometry
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.usuarios.models import EntidadPublica, Municipio

DATOS = Path(__file__).resolve().parents[2] / "data"


class Command(BaseCommand):
    help = "Carga municipios con polígono y la jurisdicción de las CAR (simulacro salvo --ejecutar)."

    def add_arguments(self, parser):
        parser.add_argument("--ejecutar", action="store_true", help="Guarda los cambios.")

    def handle(self, *args, ejecutar=False, **opciones):
        with transaction.atomic():
            nuevos, actualizados = self.cargar_municipios()
            entidades = self.cargar_entidades()
            self.stdout.write(
                f"Municipios: {nuevos} nuevos, {actualizados} actualizados. "
                f"Jurisdicciones: {entidades}."
            )
            if not ejecutar:
                transaction.set_rollback(True)
                self.stdout.write("Simulacro: no se guardó nada. Usar --ejecutar para aplicar.")
                return
        self.stdout.write(self.style.SUCCESS("Listo."))

    def cargar_municipios(self):
        nuevos = actualizados = 0
        for f in json.loads((DATOS / "municipios.geojson").read_text())["features"]:
            p = f["properties"]
            municipio = (
                Municipio.objects.filter(codigo_dane=p["codigo_dane"]).first()
                or Municipio.objects.filter(
                    codigo_dane__isnull=True,
                    nombre__iexact=p["nombre"],
                    departamento__iexact=p["departamento"],
                ).first()
            )
            if municipio is None:
                municipio, nuevos = Municipio(), nuevos + 1
            else:
                actualizados += 1
            municipio.codigo_dane = p["codigo_dane"]
            municipio.nombre = p["nombre"]
            municipio.departamento = p["departamento"]
            municipio.geom = GEOSGeometry(json.dumps(f["geometry"]), srid=4326) if f["geometry"] else None
            municipio.save()
        return nuevos, actualizados

    def cargar_entidades(self):
        resumen = []
        for nombre, codigos in json.loads((DATOS / "entidades.json").read_text()).items():
            entidad, _ = EntidadPublica.objects.get_or_create(nombre=nombre)
            municipios = Municipio.objects.filter(codigo_dane__in=codigos)
            entidad.municipios.add(*municipios)
            resumen.append(f"{nombre} {municipios.count()}/{len(codigos)}")
        return ", ".join(resumen)
