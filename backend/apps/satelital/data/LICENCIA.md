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

# Focos de calor

Vigía no versiona los focos: los descarga de cada fuente (ver `apps/satelital/clientes.py`) y
los vuelve a publicar en `/api/focos/` como datos abiertos, citando la fuente de cada uno
(campo `fuente`).

## NASA FIRMS

- **Fuente:** Fire Information for Resource Management System (LANCE/EOSDIS, NASA).
  <https://firms.modaps.eosdis.nasa.gov/>
- **Licencia:** datos de la NASA sin restricciones de uso ni de redistribución. NASA pide
  reconocer la fuente: "Datos de NASA FIRMS (https://earthdata.nasa.gov/firms), parte de
  EOSDIS de la NASA".

## INPE Queimadas

- **Fuente:** Instituto Nacional de Pesquisas Espaciais (Brasil), Programa Queimadas.
  <https://terrabrasilis.dpi.inpe.br/queimadas/>
- **Licencia:** datos públicos del Estado brasileño, de libre acceso; se cita como
  "Programa Queimadas/INPE".
