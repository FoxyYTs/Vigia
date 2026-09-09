# Vigía — App (Flutter)

Pendiente de generar. Flutter no está instalado en el entorno donde se armó
este scaffold, así que esta carpeta es un placeholder — el proyecto real se
genera con:

```bash
flutter create --org com.foxyyts.vigia --project-name vigia_app .
```

corrido **dentro de esta carpeta** (`app/`), no desde la raíz del repo.

## Antes de correr `flutter create`

Revisar en el vault de Obsidian:

- **Vigia-Mapa-Navegacion** — pantallas por rol y navegación (define la
  estructura de carpetas bajo `lib/`: qué screens existen, qué es tab bar
  vs. flujo de tarea).
- **Vigia-UML-Clases** — para los modelos del lado del cliente (DTOs que
  reflejan los serializers de la API) y los providers de estado.

## Paquetes ya decididos (ver Vigia.md § Stack Tecnológico)

`provider`, `workmanager`, `flutter_local_notifications`, `flutter_map`,
`firebase_core`, `firebase_messaging` — agregar a `pubspec.yaml` una vez
exista el proyecto generado.
