# Datos históricos: fuentes y licencias

Este directorio no versiona datos: los comandos los descargan de la fuente oficial.

## UNGRD — incendios forestales reportados

- **Fuente:** Unidad Nacional para la Gestión del Riesgo de Desastres, consolidado de
  emergencias en Datos Abiertos Colombia: conjuntos `wwkg-r6te` (2019–2022) y `rgre-6ak4`
  (2023–2024). <https://www.datos.gov.co/>
- **Licencia:** datos abiertos del Estado colombiano (Ley 1712 de 2014, transparencia y acceso
  a la información pública). Se citan como "UNGRD" en la app y en los informes.
- **Uso en Vigía:** `cargar_incendios_ungrd` (`apps/historico/clientes.py`).

## IDEAM — cambio en la superficie cubierta por bosque natural

- **Fuente:** Instituto de Hidrología, Meteorología y Estudios Ambientales, Sistema de
  Monitoreo de Bosques y Carbono (SMByC). Rasters anuales en
  <https://bart.ideam.gov.co/smbyc/Cambio%20en%20la%20superficie%20cubierta%20por%20bosque%20natural/Capas/>.
- **Licencia:** Creative Commons Atribución-CompartirIgual 4.0 (CC BY-SA 4.0), según la
  publicación del mismo conjunto en datos.gov.co (`39dh-rc72`). Las hectáreas por municipio
  que calcula Vigía son una obra derivada y se comparten con la misma licencia, citando al IDEAM.
- **Uso en Vigía:** `cargar_deforestacion_ideam` (`apps/historico/ideam.py`). Los SHA-256 de
  cada archivo están fijados en el código.
