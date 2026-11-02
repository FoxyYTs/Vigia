#!/usr/bin/env bash
# Despliega Vigía en el servidor (foxhomelab) desde el portátil:
#   1. compila la app web (el servidor no tiene el SDK de Flutter),
#   2. actualiza el código del servidor a la rama indicada (por defecto main),
#   3. copia el build web con rsync,
#   4. reconstruye y levanta los contenedores (las migraciones corren solas),
#   5. comprueba que el sitio público responda.
# Uso: scripts/desplegar.sh [rama]      Ver DESPLIEGUE.md.
set -euo pipefail

RAMA="${1:-main}"
SERVIDOR="${VIGIA_SERVIDOR:-foxyyts@172.27.0.2}"
DIR_REMOTO="${VIGIA_DIR_REMOTO:-Vigia}"
URL_PUBLICA="${VIGIA_URL:-https://vigia.foxyyts.qzz.io}"
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Compilando la app web"
(cd "$RAIZ/app" && "$FLUTTER" build web --release)
test -f "$RAIZ/app/build/web/index.html"

echo "==> Actualizando el código en $SERVIDOR:$DIR_REMOTO ($RAMA)"
ssh "$SERVIDOR" "cd $DIR_REMOTO && git fetch --quiet origin && git checkout --quiet $RAMA && git pull --quiet --ff-only origin $RAMA && git log --oneline -1"

echo "==> Copiando el build web"
rsync -az --delete "$RAIZ/app/build/web/" "$SERVIDOR:$DIR_REMOTO/app/build/web/"

echo "==> Reconstruyendo y levantando los contenedores"
ssh "$SERVIDOR" "cd $DIR_REMOTO && docker compose up -d --build --remove-orphans && docker compose ps --format '{{.Service}}: {{.Status}}'"

echo "==> Comprobando $URL_PUBLICA"
for intento in $(seq 1 20); do
    codigo=$(curl -s -o /dev/null -w '%{http_code}' "$URL_PUBLICA/api/focos/ultimo/" || true)
    [ "$codigo" = 200 ] && { echo "OK: la API responde 200"; exit 0; }
    sleep 5
done
echo "La API no respondió 200 (último código: $codigo). Revisar: ssh $SERVIDOR 'cd $DIR_REMOTO && docker compose logs --tail 50'" >&2
exit 1
