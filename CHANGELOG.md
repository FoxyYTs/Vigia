# Changelog

Cambios notables de Vigía. Formato de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y versiones según [SemVer](https://semver.org/lang/es/). Mientras el proyecto esté en 0.x, cada
versión menor corresponde a un hito del Proyecto Integrador. Las versiones 0.1–0.3 se
reconstruyeron a partir de los PR; la primera etiqueta publicada es `v0.4.0`.

## [Sin publicar]

## [0.4.1] — 2026-11-02 · Despliegue en servidor

### Agregado
- Despliegue en el servidor (foxhomelab):
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

[Sin publicar]: https://github.com/FoxyYTs/Vigia/compare/v0.4.1...develop
[0.4.1]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.1
[0.4.0]: https://github.com/FoxyYTs/Vigia/releases/tag/v0.4.0
