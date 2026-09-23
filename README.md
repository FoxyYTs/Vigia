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
- ✅ `apps/usuarios`: `Usuario`/`EntidadPublica`/`Municipio` — admin de Django registrado y
  verificado con login real.
- ⬜ `ClienteIdeam`, `ClienteUngrd`, `MotorAlertas`, `ModeloRecurrencia`,
  `Notificador`/`DespachadorNotificaciones`, endpoints REST, app Flutter.

## Licencia

[GPL v3](LICENSE). Cualquiera puede usar y modificar este código; las versiones derivadas que
se distribuyan también deben ser open source bajo GPL — coherente con que Vigía está pensado
como herramienta de interés público para entidades gubernamentales colombianas.
