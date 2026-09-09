# El build de Flutter Web (app/build/web) se copia aquí en el pipeline de
# release, una vez exista la app Flutter (ver app/README.md). Mientras
# tanto esta imagen sirve un placeholder para no romper `docker-compose up`.

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /usr/share/nginx/html \
    && echo '<h1>Vigía</h1><p>Flutter Web pendiente de build.</p>' > /usr/share/nginx/html/index.html
