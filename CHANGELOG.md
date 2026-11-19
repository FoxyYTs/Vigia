# Changelog

Cambios notables de Vigía. Formato de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y versiones según [SemVer](https://semver.org/lang/es/). Mientras el proyecto esté en 0.x, cada
versión menor corresponde a un hito del Proyecto Integrador. Las versiones 0.1–0.3 se
reconstruyeron a partir de los PR; la primera etiqueta publicada es `v0.4.0`.

## [Sin publicar]

## [0.6.0] — 2026-11-18 · Panel de administración (I6)

### Agregado
- API: `GET /api/estadisticas/?desde=&hasta=` (I6, #16) con detecciones satelitales por fuente, departamento y día, alertas por disparador y reportes por estado. Solo para administradores y staff; el administrador de una entidad con polígonos ve solo su jurisdicción. Periodo máximo de 366 días.
- App: "Gestionar Estadísticas" en el panel, con periodos de 7, 30, 90 y 365 días.
- API: `GET /api/informes/?formato=pdf|xlsx|csv&desde=&hasta=` (`ExportadorDatos`, UC8) con los mismos permisos y jurisdicción que las estadísticas. PDF: informe de apoyo a la decisión (resumen, hasta un año). Excel: hoja de resumen y detalle de focos, alertas y reportes. CSV: detalle de un conjunto (`conjunto=focos|alertas|reportes`). El detalle admite hasta 92 días. Los reportes salen sin el usuario que reportó, y el texto que empieza por `=`, `+`, `-` o `@` se neutraliza para que Excel no lo ejecute como fórmula.
- App: "Gestionar Informes" en el panel. Descarga el archivo en el navegador o lo abre en la hoja de compartir de Android (share_plus).
- API: `GET /api/historico/resumen/` (administradores y staff) con lo cargado de cada fuente histórica por año: incendios reportados a la UNGRD (cantidad, hectáreas y los que quedaron sin municipio), deforestación del IDEAM (municipios y hectáreas) y detecciones de NASA FIRMS. `POST /api/historico/ungrd/sincronizar/` (solo staff) encola la tarea `sincronizar_ungrd`.
- App: "Gestionar Históricos" en el panel, con una tabla por fuente y el botón para actualizar la UNGRD (staff).
- API: `GET /api/bot-telegram/` (administradores y staff) con el estado del bot (getMe), qué alertas recibe cada canal, los envíos y fallos de los últimos 7 días y los 20 envíos más recientes, sin exponer el token ni los ids de los chats. `POST /api/bot-telegram/probar/` (solo staff) manda un mensaje de prueba a un canal.
- App: "Gestionar Bot de Telegram" en el panel, con una tarjeta por canal y el botón de prueba (staff).
- API: `GET/PATCH /api/usuarios/` ("Gestionar Permisos"). El staff lista a todos los usuarios (con `buscar` y `rol`) y cambia su rol, entidad y si la cuenta está activa; no puede editarse a sí mismo ni a un superusuario, y desactivar una cuenta revoca sus sesiones. El administrador solo consulta a los administradores de su entidad. `GET /api/entidades/` para asignarlas.
- App: "Gestionar Permisos" como subpágina de Gestionar Usuario. Con esto todos los bloques del panel funcionan.
- API de datos abiertos: documentación OpenAPI en `/api/docs/` (Swagger UI servido localmente, compatible con la CSP) y esquema en `/api/schema/` (drf-spectacular), con la tabla de fuentes y licencias. Límite de 20.000 consultas por hora por IP para quien consulta sin sesión (`AnonRateThrottle`).
- Licencias de NASA FIRMS (verificada: sin restricciones, con reconocimiento y aviso "tal cual") e INPE Queimadas (acceso público, sin licencia publicada) en `apps/satelital/data/LICENCIA.md`. El esquema OpenAPI no tiene avisos y una prueba lo valida.

### Corregido
- Revisión previa al release:
  - Informes: el Excel fallaba (500) si la descripción de un reporte traía caracteres de control; ahora se limpian en Excel y CSV.
  - Gestionar Permisos: el rol staff ahora va con el acceso al Django Admin (`is_staff`), y cambiar el rol cierra las sesiones del usuario para que el JWT no conserve el rol anterior.
  - Gestionar Permisos: al promover a administrador hay que elegir la entidad o «todo el país»; antes quedaba nacional por defecto.
  - Límite para anónimos subido a 20.000 consultas por hora por IP: con 2.000, un salón u oficina detrás de una IP agotaba el cupo del mapa.
  - `/api/bot-telegram/probar/` y las estadísticas con fechas futuras respondían 500 en vez de 400.
  - El mensaje de prueba al canal público ya no muestra el usuario del staff, y el bot no arma el mensaje si el canal no está configurado.
  - Informes en la app: si la hoja de compartir falla, avisa en vez de quedarse callada.
  - Las exportaciones de alertas y el estado del bot ya no cargan el polígono de cada municipio.
- Bot de Telegram: si Telegram rechazaba el mensaje de prueba, la app mostraba un error genérico del servidor en vez del detalle (un 502 con JSON ahora muestra su mensaje).
- Históricos y Bot de Telegram: el botón de recargar fallaba (`setState` recibía un Future).
- Estadísticas: los días sin detecciones ahora aparecen con 0; antes el gráfico juntaba días separados por huecos.
- Estadísticas: nuevo diseño en tarjetas (totales, gráfico por día con fechas y secciones en dos columnas), con ancho máximo en pantallas anchas.
- El ciudadano ya no ve ni abre los bloques de gestión (estadísticas, informes, históricos, bot y permisos).

## [0.5.0] — 2026-11-17 · Reportes ciudadanos (I5)

### Agregado
- App: "Gestionar Reportar Focos de Incendios" (I5, #15). El ciudadano toma la foto con la cámara (sin galería), la app guarda su ubicación GPS y él pone el pin del incendio en el mapa; ve sus reportes y su estado. El administrador ve los de su jurisdicción con la miniatura y los valida o rechaza. Staff, solo lectura.
- Android: permisos de ubicación para el reporte ciudadano.

### Corregido
- La CSP de Nginx bloqueaba la lectura de la foto en la web (`blob:` en `connect-src`).

### Seguridad
- La guía de despliegue, los scripts y los comentarios ya no publican el usuario, la IP ni otros detalles del servidor. `scripts/desplegar.sh` exige `VIGIA_SERVIDOR`.

## [0.4.5] — 2026-11-07 · Hotfix de Celery

### Corregido
- `celery-worker` y `celery-beat` no arrancaban en producción: kombu 5.7 importa `packaging` sin declararlo. Ahora está en `requirements/base.txt`.

## [0.4.4] — 2026-11-07 · Mensajes de Telegram

### Cambiado
- Mensajes de Telegram más legibles: título según la certeza de la alerta, municipio, nombre real del satélite, confianza, enlace "Ver en el mapa" y sin la tarjeta de OpenStreetMap.

### Corregido
- Las alertas muestran la hora de detección en hora de Colombia; antes era la hora de creación de la alerta, en UTC.
- `MotorAlertas` guarda el municipio de la alerta, que siempre quedaba vacío.
- El despacho se limita a 15 alertas por minuto: los lotes grandes recibían 429 de Telegram y gastaban los reintentos.

## [0.4.3] — 2026-11-02 · Pulido

### Corregido
- `desplegar.sh` crea `app/build/web` en el servidor antes del rsync (#58).
- La atribución del mapa ya no repite "©" ni se corta en pantallas angostas: ahora es plegable, con una entrada por fuente.
- La sincronización de focos recupera los días perdidos tras una caída (hasta 30), en lugar de pedir siempre solo el último día. Los focos recuperados con más de 24 h no disparan alertas. En producción faltaban los focos del 20 al 30 de octubre, y por eso el mapa mostraba la misma cifra con 48 h que con 7 días (#61).

### Cambiado
- README: estado actualizado (producción, app Android en prueba interna, 241 tests).

## [0.4.2] — 2026-11-02 · Política de privacidad

### Corregido
- La política de privacidad decía que la cuenta se elimina desde la app, pero esa opción aún no existe: la eliminación se pide por correo. También aclara que el servicio es para mayores de 18 años, como se declaró en Play Store. Versión de la política: 2026-11-02.

## [0.4.1] — 2026-11-02 · Despliegue en servidor

### Agregado
- Despliegue en el servidor:
  - `scripts/desplegar.sh`: compila la web, actualiza el código, hace `docker compose up` y verifica la URL pública;
  - `scripts/respaldar_bd.sh`: `pg_dump` diario con 14 días de retención;
  - guía en `DESPLIEGUE.md`.
- `cloudflared` solo arranca con `COMPOSE_PROFILES=publico`, para que el portátil y el servidor no compartan el túnel. El puerto de Nginx se configura con `NGINX_PUERTO`.

### Agregado
- App Android lista para Play Store (prueba interna). El identificador es `com.vigia.foxyyts`, con ícono adaptable de Vigía, firma de release con una clave de subida fuera del repo (`key.properties`) y, en release, la URL de producción por defecto.

### Cambiado
- Íconos de la app web y favicon con la marca de Vigía. La política de privacidad ya tiene el correo de contacto.
- Android: `allowBackup="false"`.

## [0.4.0] — 2026-11-02 · Seguridad y Ley 1581

### Seguridad
- El backend no arranca con una `SECRET_KEY` pública o débil, y `DATABASE_URL` ya no trae una contraseña por defecto. El token del túnel sale de la línea de comandos y `cloudflared` queda fijado a una versión (#50).
- El límite de intentos no se puede evadir con `X-Forwarded-For`: Nginx toma la IP real de `CF-Connecting-IP` y los contadores viven en Redis (#30, #51).
- Sesiones revocables: el refresh rota y se revoca, dura 1 día y existe `POST /api/auth/logout/`. La app cierra la sesión solo ante un 401 (#31, #51).
- `limit_req` en login, registro y `/admin/`. Cabeceras HSTS, Permissions-Policy, COOP y CSP completa (#35, #51, #52).
- Rol por defecto `ciudadano`, reportes solo dentro de Colombia y antigüedad mínima de 24 h para que una cuenta cuente en la acumulación de alertas (#51).
- Django 5.2 LTS con versiones exactas de todas las dependencias. El backend corre sin root y la imagen no lleva compiladores (#52).

### Privacidad (Ley 1581 de 2012)
- Las fotos se re-codifican sin EXIF; la fecha y el GPS se guardan aparte, en privado. Se sirven solo con permiso (`/api/reportes/{id}/foto/`) y `/media/` deja de ser público (#52).
- Retención de las fotos: 7, 30 o 90 días según el estado del reporte (#27, #52).
- Autorización expresa de la política en el registro, eliminación de cuenta con anonimización (`DELETE /api/auth/yo/`), política en `/privacidad.html` y Google Analytics solo con consentimiento (#52).

### Cambiado
- `simular_alertas` exige `--forzar` cuando Telegram está configurado (#51).

## [0.3.0] — 2026-11-01 · Alertas, modelo predictivo e históricos

### Agregado
- **I4:** `MotorAlertas` con las 4 condiciones de alerta y notificaciones por Telegram (canales público, privado e interno), más el comando `simular_alertas` (#37).
- **I2:**
  - municipios con código DANE y polígono (#39);
  - `ModeloRecurrencia`, que predice 3 meses y se reentrena cada mes (#40);
  - capa de zonas de recurrencia en el mapa (#41).
- **I1c:**
  - incendios forestales reportados a la UNGRD, 2019–2024 (#44);
  - validación del modelo contra esos reportes (#46);
  - deforestación anual del IDEAM por municipio, 2019–2025 (#47);
  - capa "Histórico" por municipio en el mapa (#48).
- Tests de la sesión en la app (#38).

### Cambiado
- Un administrador solo ve y valida los reportes de su jurisdicción. Se agregó ruff al backend (#45).

## [0.2.0] — 2026-10-05 · App web (Parcial 1)

### Agregado
- App Flutter web: Mapa Interactivo público, inicio de sesión con JWT y panel "Gestionar X" (#28).
- Google Analytics (#36).

### Corregido
- Hallazgos de la revisión previa a la demo del Parcial 1 (#29).

## [0.1.0] — 2026-09-24 · Ingesta y API

### Agregado
- Ingesta de NASA FIRMS (tiempo real e histórico) y de INPE QUEIMADAS, con sincronización programada en Celery (#23).
- Modelos de dominio (#24).
- API REST con JWT y permisos por rol (#25).
- Filtro de focos fuera de Colombia (#26).

[Sin publicar]: https://github.com/FoxyYTs/Vigia/compare/v0.6.0...develop
[0.6.0]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.6.0
[0.5.0]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.5.0
[0.4.5]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.5
[0.4.4]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.4
[0.4.3]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.3
[0.4.2]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.2
[0.4.1]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.1
[0.4.0]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.0
