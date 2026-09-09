# Imagen única para Gunicorn, Celery Worker y Celery Beat — el comando lo
# decide docker-compose.yml (ver Vigia-UML-Despliegue, vault de Obsidian:
# los tres corren en el mismo entorno Python, no hay microservicio de ML
# ni proceso de bot separado).

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# GDAL/GEOS/PROJ — requeridos por django.contrib.gis (PostGIS) y por
# psycopg para compilar contra libpq.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gdal-bin \
        libgdal-dev \
        libgeos-dev \
        libpq-dev \
        build-essential \
        gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements/ requirements/
ARG REQUIREMENTS_FILE=requirements/production.txt
RUN pip install --no-cache-dir -r ${REQUIREMENTS_FILE}

COPY . .

# TODO: corría antes como usuario no-root ("vigia"), pero los volúmenes
# nombrados de Docker (static_files, media_files) los crea Docker con
# dueño root — collectstatic fallaba con PermissionError al escribir ahí.
# El arreglo correcto es un entrypoint que haga chown de los volúmenes
# antes de bajar privilegios (con gosu/su-exec); por ahora corre como
# root, simplificación aceptada para el MVP ya que este contenedor no
# queda expuesto directo a internet (Nginx + Cloudflare Tunnel delante).
# Ver Vigia-UML-Despliegue § Pendiente.

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
