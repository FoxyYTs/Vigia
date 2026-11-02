# Imagen única para Gunicorn, Celery Worker y Celery Beat — el comando lo
# decide docker-compose.yml (ver Vigia-UML-Despliegue, vault de Obsidian:
# los tres corren en el mismo entorno Python, no hay microservicio de ML
# ni proceso de bot separado).

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# GDAL/GEOS/PROJ para django.contrib.gis (PostGIS) y gosu para bajar a un
# usuario sin privilegios. Sin compiladores: todas las dependencias de Python
# instalan ruedas precompiladas (psycopg[binary] trae su propia libpq), así
# que la imagen no lleva gcc ni cabeceras de desarrollo.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gdal-bin \
        gosu \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --uid 1000 vigia

WORKDIR /app

COPY requirements/ requirements/
ARG REQUIREMENTS_FILE=requirements/production.txt
RUN pip install --no-cache-dir -r ${REQUIREMENTS_FILE}

COPY . .
RUN mkdir -p /app/staticfiles /app/media && chown -R vigia:vigia /app

# Arranca como root solo para ajustar los volúmenes y después corre como
# `vigia` (ver docker-entrypoint.sh).
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
