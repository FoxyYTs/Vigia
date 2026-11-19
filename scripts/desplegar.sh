#!/usr/bin/env bash
# Despliega Vigía en el servidor desde el portátil:
#   1. comprueba que el árbol local esté limpio y coincida con lo que se va a
#      desplegar (el build web sale de aquí; el código del servidor, de git),
#   2. compila la app web (el servidor no tiene el SDK de Flutter),
#   3. respalda la base del servidor (para poder volver atrás sin perder datos),
#   4. actualiza el código del servidor a la rama o el tag indicado,
#   5. copia el build web con rsync,
#   6. reconstruye y levanta los contenedores (las migraciones corren solas),
#   7. comprueba la API, la web y el estado de los contenedores.
# Uso: scripts/desplegar.sh [rama|tag]   (por defecto main)
#      Volver atrás: scripts/desplegar.sh v0.6.0        Ver DESPLIEGUE.md.
set -euo pipefail

REF="${1:-main}"
SERVIDOR="${VIGIA_SERVIDOR:?Definir VIGIA_SERVIDOR=usuario@servidor (ver DESPLIEGUE.md)}"
DIR_REMOTO="${VIGIA_DIR_REMOTO:-Vigia}"
URL_PUBLICA="${VIGIA_URL:-https://vigia.foxyyts.qzz.io}"
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

# El nombre viaja dentro de un comando remoto: solo caracteres de ramas y tags.
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Rama o tag inválido: $REF" >&2; exit 1; }

echo "==> Comprobando el árbol local"
git -C "$RAIZ" fetch --quiet --tags origin
if git -C "$RAIZ" rev-parse --verify --quiet "refs/tags/$REF" >/dev/null; then
    ESPERADO="$(git -C "$RAIZ" rev-parse "refs/tags/$REF^{commit}")"
else
    ESPERADO="$(git -C "$RAIZ" rev-parse "origin/$REF")"
fi
if [ -n "$(git -C "$RAIZ" status --porcelain)" ] || [ "$(git -C "$RAIZ" rev-parse HEAD)" != "$ESPERADO" ]; then
    echo "El portátil debe estar en $REF ($ESPERADO) y sin cambios: el build web" >&2
    echo "se compila aquí y tiene que coincidir con el código del servidor." >&2
    echo "  git checkout $REF && git pull   (o git stash)" >&2
    exit 1
fi

echo "==> Compilando la app web"
(cd "$RAIZ/app" && "$FLUTTER" build web --release)
test -f "$RAIZ/app/build/web/index.html"

echo "==> Respaldando la base del servidor"
ssh "$SERVIDOR" "DIR_VIGIA=\$HOME/$DIR_REMOTO $DIR_REMOTO/scripts/respaldar_bd.sh"

echo "==> Actualizando el código en $SERVIDOR:$DIR_REMOTO ($REF)"
ssh "$SERVIDOR" "cd $DIR_REMOTO && git fetch --quiet --tags origin && git checkout --quiet --detach $ESPERADO && git log --oneline -1"

echo "==> Copiando el build web"
ssh "$SERVIDOR" "mkdir -p $DIR_REMOTO/app/build/web"
rsync -az --delete "$RAIZ/app/build/web/" "$SERVIDOR:$DIR_REMOTO/app/build/web/"

echo "==> Reconstruyendo y levantando los contenedores"
# --wait espera los healthchecks (backend sano antes de nginx).
ssh "$SERVIDOR" "cd $DIR_REMOTO && docker compose up -d --build --remove-orphans --wait --wait-timeout 300 && docker image prune -f >/dev/null && docker compose ps --format '{{.Service}}: {{.Status}}'"

echo "==> Comprobando $URL_PUBLICA"
for intento in $(seq 1 20); do
    api=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$URL_PUBLICA/api/focos/ultimo/" || true)
    web=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$URL_PUBLICA/" || true)
    if [ "$api" = 200 ] && [ "$web" = 200 ]; then
        malos=$(ssh "$SERVIDOR" "cd $DIR_REMOTO && docker compose ps --format '{{.Service}} {{.Status}}' | grep -Ei 'restarting|unhealthy' || true")
        [ -z "$malos" ] && { echo "OK: la API y la web responden 200 y los contenedores están sanos"; exit 0; }
        echo "Contenedores con problemas: $malos" >&2
        exit 1
    fi
    sleep 5
done
echo "No respondió 200 (API: $api, web: $web). Revisar: ssh $SERVIDOR 'cd $DIR_REMOTO && docker compose logs --tail 50'" >&2
exit 1
