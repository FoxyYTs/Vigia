#!/usr/bin/env bash
# Respaldo diario de la base de datos de Vigía (corre en el servidor por cron).
# Guarda un pg_dump comprimido y conserva los últimos 14 días.
#   crontab (una vez al día):  $HOME/Vigia/scripts/respaldar_bd.sh >> "$HOME/respaldo.log" 2>&1
set -euo pipefail

DIR_VIGIA="${DIR_VIGIA:-$HOME/Vigia}"
DESTINO="${DESTINO:-$HOME/backups/vigia}"
DIAS="${DIAS:-14}"
mkdir -p "$DESTINO"
chmod 700 "$DESTINO"

archivo="$DESTINO/vigia-$(date +%F-%H%M).dump"
cd "$DIR_VIGIA"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$archivo.tmp"
mv "$archivo.tmp" "$archivo"
chmod 600 "$archivo"
find "$DESTINO" -name 'vigia-*.dump' -mtime +"$DIAS" -delete
echo "$(date -Iseconds) respaldo: $archivo ($(du -h "$archivo" | cut -f1))"
