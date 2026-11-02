#!/bin/sh
# El contenedor arranca como root solo para ajustar los volúmenes nombrados
# (Docker los crea con dueño root) y luego baja a un usuario sin privilegios.
# Si ya arranca con otro usuario (p. ej. `docker compose run --user …` para las
# pruebas), no toca nada.
set -e
if [ "$(id -u)" = "0" ]; then
    chown -R vigia:vigia /app/staticfiles /app/media
    exec gosu vigia "$@"
fi
exec "$@"
