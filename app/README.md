# Vigía — App (Flutter)

Cliente web y Android de Vigía (incremento I5, issue #15). Primera versión:
**Mapa Interactivo** (público) e **Iniciar Sesión** con JWT, siguiendo el mapa de
navegación del vault (`Vigia-Mapa-Navegacion`):

```
Vigía ─┬─ Mapa Interactivo          /         sin cuenta
       └─ Iniciar Sesión            /#/login
            └─ Gestionar X (panel)  /#/panel  con sesión
```

- **Mapa Interactivo:** focos de calor de NASA FIRMS e INPE QUEIMADAS sobre
  OpenStreetMap, con filtros de rango (24 h, 48 h, 7 días, 31 días + fecha de
  corte) y de fuente, contador por fuente, leyenda y detalle al tocar un foco.
  Arranca en la fecha del último foco cargado (`GET /api/focos/ultimo/`) para que
  no quede vacío si la ingesta lleva días detenida. Se dibujan como máximo 5.000
  focos (páginas de 500 en paralelo); si hay más, el contador lo avisa.
- **Iniciar Sesión:** validación del formulario en el cliente, mensajes de error
  en español (credenciales, límite de intentos, sin conexión) y tokens guardados
  con `flutter_secure_storage`. El access se renueva con el refresh al expirar.
- **Panel (bloques "Gestionar X"):** "Gestionar Usuario" muestra el perfil real
  (`GET /api/auth/yo/`); los demás bloques están marcados como próximo
  incremento. Desde aquí se cierra la sesión.

## Estructura

```
lib/
├── config/app_config.dart      URL de la API (--dart-define)
├── core/theme/                 paleta y tema del design system de Stitch
├── data/api/vigia_api.dart     cliente HTTP y traducción de errores
├── data/models/                DTO de los serializers (Foco, Usuario, JWT)
├── data/storage/               almacenamiento de tokens (seguro / memoria)
├── providers/                  AuthProvider, FocosProvider (provider)
├── screens/                    login, mapa, panel y rutas
└── widgets/                    mapa, filtros, detalle, marca
design/                         capturas de Stitch e IDs (design/README.md)
```

## Configuración

La URL de la API **no está en el código** (Twelve-Factor):

| Plataforma | Por defecto | Cambiarla |
|---|---|---|
| Web | `/api/` del mismo origen (Nginx sirve la app y la API, no hace falta CORS) | `--dart-define=API_BASE_URL=https://.../api/` |
| Android | `http://10.0.2.2:8080/api/` (emulador) | `--dart-define=API_BASE_URL=https://vigia.foxyyts.qzz.io/api/` |

## Correr la demo

Flutter no está en el `PATH` de la máquina de desarrollo:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export CHROME_EXECUTABLE=/usr/bin/chromium
```

**Opción A — como en producción (Nginx en `http://localhost:8080`):**

```bash
cd app
flutter pub get
flutter build web --release      # genera app/build/web, que Nginx monta
cd ..
docker compose build backend nginx
docker compose up -d backend nginx
```

Abrir `http://localhost:8080/` (o `https://vigia.foxyyts.qzz.io` si el túnel está
arriba). El build hay que hacerlo **antes** de levantar Nginx: si `app/build/web`
no existe, Docker crea la carpeta vacía y Nginx responde 403.

**Opción B — desarrollo con recarga en caliente:** la app corre en otro puerto,
así que el navegador bloquearía la API por CORS. Se apunta a la API por su URL y
se abre Chromium sin la política de mismo origen (solo para desarrollo local):

```bash
cd app
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8080/api/ \
  --web-browser-flag=--disable-web-security
```

Datos frescos para la demo (si Celery Beat no está corriendo):

```bash
docker compose exec backend python manage.py shell \
  -c "from apps.satelital.tasks import sincronizar_focos; print(sincronizar_focos())"
```

## Pruebas

```bash
cd app
flutter analyze
flutter test
```

- `test/data/vigia_api_test.dart`: cliente de la API con `MockClient` (URL,
  cuerpo, cabecera Bearer, parámetros de focos y cada error traducido).
- `test/providers/focos_provider_test.dart`: paginación en paralelo, límite de
  focos dibujados y rango pedido al cambiar la ventana.
- `test/screens/login_screen_test.dart`: validaciones del formulario, error de
  credenciales, login correcto y etiqueta accesible del botón de contraseña.
