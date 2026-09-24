# Vigía

Sistema de alerta temprana para la detección y notificación de incendios forestales en Colombia.
Integra datos satelitales (NASA FIRMS, INPE QUEIMADAS), históricos de deforestación e incendios
(IDEAM, UNGRD) y un modelo de aprendizaje automático que identifica zonas de incendio recurrente,
para notificar oportunamente a entidades públicas y ciudadanos.

Proyecto Integrador — Ingeniería Informática, Politécnico Colombiano Jaime Isaza Cadavid (2026-2).
Desarrollo individual (José Andrés Daza Gallego).

## Stack

- **Backend:** Django REST Framework, PostgreSQL + PostGIS, Celery + Celery Beat, Redis,
  simplejwt
- **Aprendizaje automático:** pandas, scikit-learn
- **Frontend / Móvil:** Flutter (web y móvil desde el mismo código)
- **Infraestructura:** Docker Compose, Nginx, Cloudflare Tunnel
- **Notificaciones:** Firebase Cloud Messaging, bot de Telegram (3 canales)
- **Pruebas:** pytest

## Estructura

```
.
├── backend/           # Django REST Framework
│   ├── config/         # settings (base/local/production), celery.py, urls.py
│   └── apps/           # usuarios · satelital · historico · prediccion ·
│                        # reportes · alertas · notificaciones · administracion
├── app/                # Flutter (pendiente de `flutter create`, ver app/README.md)
├── nginx/              # reverse proxy + estáticos de Flutter Web
└── docker-compose.yml
```

Cada app de `backend/apps/` corresponde a un bloque del modelo de datos y del diagrama de
clases de servicios del diseño — ver los `models.py` de cada una para la referencia exacta.

## Levantar el entorno

```bash
cp .env.example .env   # y llenar con credenciales reales
docker compose up --build
```

La API queda en `http://localhost:8080/api/`, el admin de Django en
`http://localhost:8080/admin/`.

También disponible públicamente vía Cloudflare Tunnel: https://vigia.foxyyts.qzz.io

## API

Todo cuelga de `/api/`. Auth con JWT (`Authorization: Bearer <access>`); el token incluye el `rol`.

| Endpoint | Quién | Qué hace |
|---|---|---|
| `POST auth/registro/` | Anónimo | Crea un **ciudadano** (el rol nunca lo elige el cliente) |
| `POST auth/token/`, `auth/token/refresh/` | Anónimo | Login / renovar acceso |
| `GET auth/yo/` | Autenticado | Perfil del usuario |
| `GET municipios/` | Anónimo | Catálogo (`?departamento=`) |
| `GET focos/` | Anónimo | Focos para el mapa: `desde`, `hasta` (48 h por defecto, máx. 31 días), `fuente`, `bbox` |
| `GET zonas-recurrentes/` | Anónimo | Zonas de la corrida más reciente del modelo (`min_puntaje`) |
| `POST reportes/` (multipart) | Ciudadano | Crea un reporte con foto y las dos ubicaciones |
| `GET reportes/` | Ciudadano (los suyos) / Administrador y Staff (todos, Staff solo lectura) | `?estado=` |
| `POST reportes/{id}/validar/`, `rechazar/` | Administrador | 409 si ya estaba resuelto |
| `GET alertas/` | Autenticado | `?tipo=` |
| `GET notificaciones/`, `POST notificaciones/{id}/marcar-leida/` | Autenticado | Solo las propias |

Registro, login y creación de reportes tienen límite de intentos. Un administrador aún ve
todos los reportes: el filtro por jurisdicción necesita la geometría de `Municipio`.

## Ramas

GitFlow: `main` solo para releases estables, `develop` como rama de integración,
`feature/<nombre>` para trabajo en curso.

## Estado

Diseño completo (modelo de datos, diagramas UML, estructura de repo). En implementación:

- ✅ `apps/satelital`: `FocoIncendio` + `ClienteNasaFirms` (tiempo real e histórico) +
  `ClienteInpeQueimadas` (WFS, capa `bdqueimadas2:focos` filtrada por Colombia). Probados contra las
  APIs reales; 20/20 tests con Postgres real. La tarea de Celery `sincronizar_focos` corre cada 3 h
  y cada fuente falla de forma aislada.
- ✅ Histórico: `python manage.py cargar_historico_firms` (VIIRS NOAA-20, 2018-04 → hoy, idempotente).
- ✅ Filtro de Colombia: FIRMS se consulta con un rectángulo que incluye países vecinos y mar
  (57 % de los focos caían fuera), así que se descartan al ingerir con un contorno aproximado
  (`apps/satelital/data/`, CC BY 4.0). `depurar_focos_fuera_de_colombia` limpia lo ya cargado.
- ✅ `apps/usuarios`: `Usuario`/`EntidadPublica`/`Municipio` — admin de Django registrado y
  verificado con login real.
- ✅ Modelos de dominio completos, API REST con JWT y permisos por rol (109 tests).
- ⬜ `ClienteIdeam`, `ClienteUngrd`, `MotorAlertas`, `ModeloRecurrencia`,
  `Notificador`/`DespachadorNotificaciones`, app Flutter.

## Licencia

[GPL v3](LICENSE). Cualquiera puede usar y modificar este código; las versiones derivadas que
se distribuyan también deben ser open source bajo GPL — coherente con que Vigía está pensado
como herramienta de interés público para entidades gubernamentales colombianas.
