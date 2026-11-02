# Diseño de pantallas (Stitch)

Las pantallas se diseñaron en [Stitch](https://stitch.withgoogle.com) por MCP y se
tradujeron a widgets de Flutter. Las capturas de esta carpeta son la referencia;
la app no usa el HTML generado.

| Elemento | ID |
|---|---|
| Proyecto "Vigía" | `projects/16443854214880665642` |
| Design system "Vigía — Alertas ambientales" | `assets/68026785284242981` |
| Iniciar Sesión (escritorio) | `screens/2706ac36ce5a4f0e8f932e7ada5386bc` → `stitch/login-escritorio.png` |
| Mapa Interactivo (escritorio) | `screens/fb582fd1801c497e8a6d4a530c97ad68` → `stitch/mapa-escritorio.png` |
| Mapa Interactivo (móvil) | `screens/dcc5eb9d82fe4cb3b9f8f139347c7885` → `stitch/mapa-movil.png` |

## Design system

- Primario verde bosque `#1B5E3A` (barra superior, botones) con texto blanco.
- Acento naranja fuego `#B4410F` para alertas; errores `#B3261E` siempre con
  icono y texto.
- Focos: NASA FIRMS en naranja `#D9531E`, INPE QUEIMADAS en violeta rojizo
  `#7B1E5A`, con leyenda (el color nunca es la única señal).
- Superficie `#F4F6F3`, tarjetas blancas con borde `#D5DBD3`, radio de 8 px.
- Contraste WCAG AA, etiquetas visibles en los campos y foco visible.

Los tokens están en `lib/core/theme/vigia_theme.dart`.

## Qué se dejó fuera del diseño de Stitch

Stitch agregó elementos que no existen en el sistema o no corresponden a este
incremento, y no se implementaron para no mostrar funciones falsas: "Recordar
sesión", "¿Olvidó su contraseña?", "Notificar a Bomberos / UNGRD", "Ver histórico
del punto", el selector de capas (topográfico/satélite), la descarga GeoJSON/CSV
y el "nivel de alerta" por región. Las cifras de las maquetas son de ejemplo.
