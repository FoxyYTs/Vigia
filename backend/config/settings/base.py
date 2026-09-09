"""
Settings compartidos entre local.py y production.py.

Secretos vía .env + django-environ (decisión registrada en
Vigia-Roadmap-Desarrollo, vault de Obsidian) — nunca hardcodear
credenciales aquí. Ver .env.example en la raíz del repo para las
variables esperadas.
"""

from datetime import timedelta
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()

# El build context del Dockerfile es solo backend/ (ver Vigia-UML-Despliegue),
# así que dentro del contenedor no existe un .env físico en BASE_DIR.parent
# — ahí las variables ya llegan inyectadas por `env_file:` de
# docker-compose.yml. read_env() es solo para desarrollo local fuera de
# Docker; por eso se guarda condicionado a que el archivo exista.
_dotenv_path = BASE_DIR.parent / ".env"
if _dotenv_path.exists():
    environ.Env.read_env(_dotenv_path)

SECRET_KEY = env("DJANGO_SECRET_KEY")
DEBUG = env.bool("DJANGO_DEBUG", default=False)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])

AUTH_USER_MODEL = "usuarios.Usuario"

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.gis",  # PostGIS
    # Terceros
    "rest_framework",
    "rest_framework_simplejwt",
    "django_celery_beat",
    # Apps del dominio — ver Vigia-UML-Clases (vault) § Persistencia/Servicios
    "apps.usuarios",
    "apps.satelital",
    "apps.historico",
    "apps.prediccion",
    "apps.reportes",
    "apps.alertas",
    "apps.notificaciones",
    "apps.administracion",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# Base de datos — PostGIS (ver Vigia-Modelo-Datos § geography(Point,4326))
DATABASES = {
    "default": env.db("DATABASE_URL", default="postgis://vigia:vigia@db:5432/vigia"),
}
DATABASES["default"]["ENGINE"] = "django.contrib.gis.db.backends.postgis"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "es-co"
TIME_ZONE = "America/Bogota"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Django REST Framework + simplejwt
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticatedOrReadOnly",
    ),
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
}

# Celery (ver Vigia-UML-Despliegue § Redis "broker")
CELERY_BROKER_URL = env("REDIS_URL", default="redis://redis:6379/0")
CELERY_RESULT_BACKEND = env("REDIS_URL", default="redis://redis:6379/0")
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE

# Credenciales e integraciones externas — ver Vigia-Credenciales-APIs
# (vault de Obsidian) para el proceso de registro de cada una y el
# formato exacto de uso (MAP_KEY en la URL, X-App-Token como header, etc.)
NASA_FIRMS_MAP_KEY = env("NASA_FIRMS_MAP_KEY", default="")
INPE_QUEIMADAS_WFS_URL = env(
    "INPE_QUEIMADAS_WFS_URL",
    default="https://terrabrasilis.dpi.inpe.br/queimadas/geoserver/wfs",
)
UNGRD_SOCRATA_APP_TOKEN = env("UNGRD_SOCRATA_APP_TOKEN", default="")
UNGRD_SOCRATA_APP_SECRET = env("UNGRD_SOCRATA_APP_SECRET", default="")
UNGRD_DATASET_ID = env("UNGRD_DATASET_ID", default="")
TELEGRAM_BOT_TOKEN = env("TELEGRAM_BOT_TOKEN", default="")
TELEGRAM_CANAL_PUBLICO_ID = env("TELEGRAM_CANAL_PUBLICO_ID", default="")
TELEGRAM_CANAL_PRIVADO_ID = env("TELEGRAM_CANAL_PRIVADO_ID", default="")
TELEGRAM_CANAL_INTERNO_ID = env("TELEGRAM_CANAL_INTERNO_ID", default="")
