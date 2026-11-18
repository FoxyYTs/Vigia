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
- **Licencia:** se comparte abiertamente y sin restricciones, según la EOSDIS Data Use and
  Citation Guidance (<https://www.earthdata.nasa.gov/engage/open-data-services-software-policies/data-use-guidance>).
- **Condiciones al redistribuir:** reconocer la fuente ("We acknowledge the use of data and
  imagery from LANCE FIRMS operated by NASA's Earth Science Data and Information System
  (ESDIS) with funding provided by NASA Headquarters") y replicar o enlazar su aviso: los
  datos se entregan "tal cual" y el casi tiempo real no tiene calidad científica.
  Verificado el 18-nov-2026.

## INPE Queimadas

- **Fuente:** Instituto Nacional de Pesquisas Espaciais (Brasil), Programa Queimadas.
  <https://terrabrasilis.dpi.inpe.br/queimadas/>
- **Licencia:** INPE no publica una licencia específica para estos datos (revisado el
  18-nov-2026). Son de acceso público bajo la Política de Datos Abiertos del gobierno federal
  de Brasil (Decreto 8.777 de 2016); el portal gov.br del INPE usa CC BY-ND 3.0 para su
  contenido web, pero no dice que aplique a los datos. Vigía los cita como "Programa
  Queimadas/INPE".
- **Pendiente:** confirmar la licencia y la forma de citarlos con el Programa Queimadas
  (cienciasdaterra@inpe.br) antes de un uso comercial o masivo.
