# Despliegue de Vigía

Producción corre en **foxhomelab** (`foxyyts@172.27.0.2`, por ZeroTier) con Docker Compose,
en `~/Vigia`, sobre la rama `main`. El público entra por `https://vigia.foxyyts.qzz.io` gracias
al túnel de Cloudflare de Vigía (servicio `cloudflared`, perfil `publico`). La app Android
usa esa misma URL.

## Portátil y servidor: no correr el túnel en los dos

`cloudflared` solo arranca con `COMPOSE_PROFILES=publico`, que está puesto únicamente en el
`.env` del servidor. Si el portátil también lo corriera, Cloudflare repartiría el tráfico
entre las dos máquinas.

Por la misma razón, el `.env` del portátil lleva los `TELEGRAM_*` vacíos. Si no, el Celery de
desarrollo también mandaría alertas reales al canal.

## Desplegar una versión

Desde el portátil, con `main` ya actualizado (release por PR `develop` → `main`):

```bash
scripts/desplegar.sh          # o scripts/desplegar.sh <rama> para probar otra rama
```

El script compila la app web, hace `git pull` en el servidor, copia `app/build/web` con
rsync, corre `docker compose up -d --build` (las migraciones se aplican al arrancar el
backend) y comprueba que la API pública responda 200.

## `.env` del servidor (`~/Vigia/.env`, permisos 600)

Parte de `.env.example`. Diferencias con el portátil:

| Variable | Servidor |
|---|---|
| `DJANGO_SECRET_KEY`, `POSTGRES_PASSWORD`, `DATABASE_URL` | Propias del servidor, distintas a las del portátil |
| `COMPOSE_PROFILES` | `publico` (arranca `cloudflared`) |
| `NGINX_PUERTO` | `127.0.0.1:8090` (el 8080 es de Pi-hole) |
| `TELEGRAM_*`, `NASA_FIRMS_MAP_KEY`, `UNGRD_SOCRATA_APP_TOKEN`, `CLOUDFLARE_TUNNEL_TOKEN` | Los reales |

## Respaldos

`scripts/respaldar_bd.sh` corre por cron a las 02:30. Hace un `pg_dump -Fc` en
`~/backups/vigia/` y conserva 14 días.

Restaurar un respaldo:

```bash
cd ~/Vigia
docker compose stop backend celery-worker celery-beat
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < ~/backups/vigia/vigia-AAAA-MM-DD-HHMM.dump
docker compose up -d
```

Las fotos de los reportes están en el volumen `vigia_media_files`. No entran en el
`pg_dump`; si importan, hay que respaldar también ese volumen.

## Volver a la versión anterior

```bash
ssh foxyyts@172.27.0.2 'cd ~/Vigia && git checkout v0.X.Y && docker compose up -d --build'
```

Si la versión nueva traía migraciones, primero hay que restaurar el respaldo de la base del
día del despliegue.

## Pendientes de configuración (panel de Cloudflare)

- ✅ **Access** sobre `vigia.foxyyts.qzz.io/admin/` (configurado el 2-nov-2026).
