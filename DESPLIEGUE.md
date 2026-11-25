# Despliegue de Vigía

Producción corre en un servidor propio, accesible por SSH en una red privada, con Docker
Compose, en `~/Vigia`, sobre la rama `main`. El público entra por `https://vigia.foxyyts.qzz.io` gracias
al túnel de Cloudflare de Vigía (servicio `cloudflared`, perfil `publico`). La app Android
usa esa misma URL.

## Portátil y servidor: no correr el túnel en los dos

`cloudflared` solo arranca con `COMPOSE_PROFILES=publico`, que está puesto únicamente en el
`.env` del servidor. Si el portátil también lo corriera, Cloudflare repartiría el tráfico
entre las dos máquinas.

Por la misma razón, el `.env` del portátil lleva los `TELEGRAM_*` vacíos. Si no, el Celery de
desarrollo también mandaría alertas reales al canal.

## Desplegar una versión

Desde el portátil, en `main` actualizado y sin cambios locales (release por PR `develop` → `main`):

```bash
export VIGIA_SERVIDOR=usuario@servidor
scripts/desplegar.sh          # main; o scripts/desplegar.sh <rama|tag>
```

El script:

1. Se niega a seguir si el portátil tiene cambios o no está en el commit que se va a
   desplegar: el build web se compila en el portátil y debe coincidir con el código del
   servidor.
2. Compila la app web.
3. Corre `respaldar_bd.sh` en el servidor (respaldo previo al despliegue).
4. Deja el servidor en ese commit exacto (`git checkout --detach`).
5. Copia `app/build/web` con rsync.
6. Corre `docker compose up -d --build --wait` (las migraciones se aplican al arrancar el
   backend; `--wait` espera los healthchecks) y borra las imágenes viejas.
7. Comprueba que la API y la web respondan 200 y que ningún contenedor quede `restarting`
   o `unhealthy`.

## `.env` del servidor (`~/Vigia/.env`, permisos 600)

Parte de `.env.example`. Diferencias con el portátil:

| Variable | Servidor |
|---|---|
| `DJANGO_SECRET_KEY`, `POSTGRES_PASSWORD`, `DATABASE_URL` | Propias del servidor, distintas a las del portátil |
| `COMPOSE_PROFILES` | `publico` (arranca `cloudflared`) |
| `NGINX_PUERTO` | Un puerto libre del servidor, siempre en `127.0.0.1` |
| `TELEGRAM_*`, `NASA_FIRMS_MAP_KEY`, `UNGRD_SOCRATA_APP_TOKEN`, `CLOUDFLARE_TUNNEL_TOKEN` | Los reales |

## Respaldos

`scripts/respaldar_bd.sh` corre a diario por cron (02:30) y antes de cada despliegue. Hace un
`pg_dump -Fc` en `~/backups/vigia` y conserva 14 días. Para el cron:

```
30 2 * * * $HOME/Vigia/scripts/respaldar_bd.sh >> $HOME/respaldo.log 2>&1
```

Los respaldos están en el mismo disco del servidor: para sobrevivir a una falla del disco
conviene copiarlos a otro equipo (pendiente). Para comprobar que un respaldo sirve:
`docker compose exec -T db pg_restore --list < ruta/al/respaldo.dump | head`.

Restaurar un respaldo:

```bash
cd ~/Vigia
docker compose stop backend celery-worker celery-beat
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < ruta/al/vigia-AAAA-MM-DD-HHMM.dump
docker compose up -d
```

Las fotos de los reportes están en el volumen `vigia_media_files`. No entran en el
`pg_dump`; si importan, hay que respaldar también ese volumen.

## Volver a la versión anterior

```bash
git checkout v0.X.Y
scripts/desplegar.sh v0.X.Y
```

Así vuelven juntos el código del servidor y la app web (que no está en git: se compila en el
portátil). Si la versión nueva traía migraciones, antes hay que restaurar el respaldo que el
script tomó al desplegarla (el más reciente de `~/backups/vigia` antes de esa hora).

## App Android (AAB para Play Store)

Desde `app/`, con `app/android/key.properties` apuntando a la clave de subida:

```bash
V=0.X.Y+N   # la versión de pubspec.yaml
flutter build appbundle --release --obfuscate \
  --dart-define=STADIA_API_KEY=<clave de Stadia Maps> \
  --split-debug-info=$HOME/Proyectos/apps/Vigia/playstore/simbolos/$V
cp build/app/outputs/bundle/release/app-release.aab ~/Proyectos/apps/Vigia/playstore/app-release-$V.aab
```

`--obfuscate` deja `libapp.so` un 17 % más liviano. Los símbolos quedan fuera del repo y
son los que permiten leer las trazas de error de esa versión con `flutter symbolize`; hay
que guardarlos junto al AAB. R8 ya viene activo en release y los tiles del mapa ya se
cachean en disco (flutter_map 8).

Para medir el mapa en un celular conectado por USB (resumen en
`app/build/mapa_31d_*.timeline_summary.json`):

```bash
flutter drive --profile --no-dds -d <id> \
  --dart-define=API_BASE_URL=https://vigia.foxyyts.qzz.io/api/ \
  --driver=test_driver/rendimiento_driver.dart \
  --target=integration_test/rendimiento_mapa_test.dart
```

## Pendientes de configuración (panel de Cloudflare)

- ✅ **Access** sobre `vigia.foxyyts.qzz.io/admin/` (configurado el 2-nov-2026).
