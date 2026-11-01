"""
Genera municipios.geojson cruzando dos fuentes abiertas (se corre una sola vez;
el resultado queda versionado y `cargar_municipios` lo lee sin red):

- Polígonos: geoBoundaries COL ADM2 simplificado (origen DANE 2020, CC BY 4.0).
  No trae código DANE ni departamento, y hay nombres repetidos ("San Rafael").
- Códigos: DIVIPOLA en datos.gov.co (gdxc-w37w), con código DANE, departamento
  y la ubicación de la cabecera municipal.

El cruce es espacial: a cada municipio de DIVIPOLA le toca el polígono que
contiene su cabecera, así los nombres repetidos no importan. Excepción: si
hay un polígono cercano (<50 km) con el mismo nombre, gana el más cercano de
esos. Pasa con Margarita (Bolívar), cuya cabecera cae en un municipio vecino,
y con los dos Colón (Nariño y Putumayo), que están a unos 40 km.

geoBoundaries (2020) aún trae Mapiripana como unidad aparte; en 2019 se
fusionó con Barrancominas, así que su polígono se une al de ese municipio.
Al revés, Nuevo Belén de Bajirá (Chocó) es posterior a 2020 y no tiene
polígono propio: queda sin geometría en vez de quedarse con el de Riosucio.

    python manage.py shell -c "from apps.usuarios.data.preparar_municipios import main; \
        main('<adm2_simplified.geojson>', '<divipola.json>')"
"""

import json
import unicodedata
from collections import Counter
from pathlib import Path

from django.contrib.gis.geos import GEOSGeometry, MultiPolygon, Point

SALIDA = Path(__file__).parent / "municipios.geojson"
TOLERANCIA_SIMPLIFICACION = 0.002  # grados, ~200 m: suficiente para asignar zonas de 11 km
RADIO_MISMO_NOMBRE = 0.45  # grados, ~50 km
# Polígono de geoBoundaries → código DANE del municipio que lo absorbió.
FUSIONES = {"Mapiripana": "94343"}  # Barrancominas, Guainía
# Municipios de DIVIPOLA más nuevos que los polígonos de geoBoundaries.
SIN_POLIGONO = {"27493"}  # Nuevo Belén de Bajirá, Chocó
MINUSCULAS = {"de", "del", "la", "las", "los", "y", "el"}


def titulo(texto: str) -> str:
    palabras = texto.lower().split()
    return " ".join(
        p.upper() if p == "d.c." else p if i and p in MINUSCULAS else p[:1].upper() + p[1:]
        for i, p in enumerate(palabras)
    )


def _normalizar(texto: str) -> str:
    sin_tildes = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return sin_tildes.split("(")[0].strip().lower()


def preparar(ruta_poligonos: str, ruta_divipola: str) -> dict:
    poligonos = [
        (f["properties"]["shapeName"], GEOSGeometry(json.dumps(f["geometry"]), srid=4326))
        for f in json.loads(Path(ruta_poligonos).read_text())["features"]
    ]
    preparados = [(nombre, geom, geom.prepared) for nombre, geom in poligonos]
    usados, asignados, salida, sin_poligono = set(), [], [], []
    for m in json.loads(Path(ruta_divipola).read_text()):
        propiedades = {
            "codigo_dane": m["cod_mpio"],
            "nombre": titulo(m["nom_mpio"]),
            "departamento": titulo(m["dpto"]),
        }
        if m["cod_mpio"] in SIN_POLIGONO:
            salida.append({"type": "Feature", "properties": propiedades, "geometry": None})
            continue
        cabecera = Point(float(m["longitud"].replace(",", ".")), float(m["latitud"].replace(",", ".")), srid=4326)
        mismo_nombre = sorted(
            (
                i for i, (nombre, geom, _) in enumerate(preparados)
                if _normalizar(nombre) == _normalizar(m["nom_mpio"]) and geom.distance(cabecera) < RADIO_MISMO_NOMBRE
            ),
            key=lambda i: preparados[i][1].distance(cabecera),
        )
        candidatos = mismo_nombre or [i for i, (_, _, p) in enumerate(preparados) if p.contains(cabecera)]
        if not candidatos:
            # Cabecera en la costa o sobre un límite que la simplificación movió: el más cercano.
            candidatos = [min(range(len(preparados)), key=lambda i: preparados[i][1].distance(cabecera))]
            sin_poligono.append(m["cod_mpio"])
        i = candidatos[0]
        _, geom, _ = preparados[i]
        asignados.append(i)
        usados.add(i)
        for nombre_fusionado, codigo in FUSIONES.items():
            if codigo == m["cod_mpio"]:
                j = next(k for k, (n, _, _) in enumerate(preparados) if n == nombre_fusionado)
                geom = geom.union(preparados[j][1])
                usados.add(j)
        geom = geom.simplify(TOLERANCIA_SIMPLIFICACION, preserve_topology=True)
        if geom.geom_type == "Polygon":
            geom = MultiPolygon(geom, srid=4326)
        coords = json.loads(geom.json)
        coords["coordinates"] = _redondear(coords["coordinates"])
        salida.append({
            "type": "Feature",
            "properties": propiedades,
            "geometry": coords,
        })
    return {
        "geojson": {"type": "FeatureCollection", "features": salida},
        "sin_poligono": sin_poligono,
        "poligonos_sin_usar": [poligonos[i][0] for i in range(len(poligonos)) if i not in usados],
        "poligonos_repetidos": [preparados[i][0] for i, n in Counter(asignados).items() if n > 1],
    }


def _redondear(c):
    return [_redondear(x) for x in c] if isinstance(c[0], list) else [round(c[0], 4), round(c[1], 4)]


def main(ruta_poligonos, ruta_divipola):
    r = preparar(ruta_poligonos, ruta_divipola)
    SALIDA.write_text(json.dumps(r["geojson"], ensure_ascii=False, separators=(",", ":")))
    print(f"{len(r['geojson']['features'])} municipios → {SALIDA}")
    print(f"Cabecera fuera de su polígono (se usó el más cercano): {r['sin_poligono']}")
    print(f"Polígonos sin municipio asignado: {r['poligonos_sin_usar']}")
    print(f"Municipios que comparten polígono: {r['poligonos_repetidos']}")

