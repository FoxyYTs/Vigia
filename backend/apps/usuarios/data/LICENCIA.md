# municipios.geojson

Los 1.122 municipios y áreas no municipalizadas de Colombia con código DANE,
departamento y polígono. Lo carga `python manage.py cargar_municipios`.

- **Polígonos:** geoBoundaries, Colombia ADM2 (gbOpen, versión simplificada), con origen en
  el DANE (2020). https://www.geoboundaries.org/api/current/gbOpen/COL/ADM2/
  Licencia **Creative Commons Attribution 4.0 (CC BY 4.0)**.
- **Códigos, nombres y departamentos:** DIVIPOLA del DANE publicada en Datos Abiertos
  Colombia (conjunto `gdxc-w37w`). https://www.datos.gov.co/resource/gdxc-w37w.json
  Datos abiertos del Estado colombiano (Ley 1712 de 2014).
- **Derivación:** `preparar_municipios.py`, en esta misma carpeta (descargado el 1-nov-2026).
  - A cada municipio de DIVIPOLA le toca el polígono que contiene su cabecera.
  - Si hay un polígono cercano con el mismo nombre, gana ese.
  - Geometría simplificada a ~200 m y coordenadas redondeadas a 4 decimales.
- **Excepciones:**
  - Mapiripana se une a Barrancominas (fusionadas en 2019).
  - Nuevo Belén de Bajirá (27493) no tiene polígono, porque la fuente es anterior a su creación.

Es una geometría aproximada para asignar focos y zonas a un municipio, no un límite oficial.

# entidades.json

Municipios de la jurisdicción de cada CAR, por código DANE.

- **Cornare:** los 26 municipios del oriente antioqueño (Ley 60 de 1983, que crea Cornare).
- **Corantioquia:** pendiente, porque no se encontró una lista oficial confiable de sus 80
  municipios. No se carga a ojo.
