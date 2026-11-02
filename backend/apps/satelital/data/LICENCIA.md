# colombia.geojson

Contorno nacional de Colombia usado para descartar focos fuera del país
(ver `apps/satelital/geografia.py`).

- **Fuente:** geoBoundaries, Colombia ADM2 (gbOpen), cuyo origen es el DANE (2020).
  https://www.geoboundaries.org/api/current/gbOpen/COL/ADM2/
- **Licencia:** Creative Commons Attribution 4.0 (CC BY 4.0).
- **Derivación:** se unió (`ST_Union`) la versión *simplificada* de las 1.122 unidades
  municipales y se redondearon las coordenadas a 4 decimales (~11 m). No incluye San
  Andrés y Providencia. Es un contorno aproximado para filtrar detecciones, no una
  frontera oficial.
