# La app Flutter Web no se copia en la imagen: docker-compose.yml monta
# app/ y Nginx sirve app/build/web (ver nginx.conf y app/README.md).
# Esta imagen solo trae la página que se muestra, con un 503, mientras ese
# build no exista. Compilar la app dentro de la imagen (multi-stage) queda
# como mejora pendiente.

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /usr/share/nginx/html \
    && printf '%s\n' \
       '<!doctype html><html lang="es"><meta charset="utf-8"><title>Vigía</title>' \
       '<h1>Vigía</h1><p>La aplicación web todavía no está compilada.</p>' \
       '<p>Correr <code>flutter build web --release</code> dentro de <code>app/</code> y recargar.</p></html>' \
       > /usr/share/nginx/html/sin-build.html
