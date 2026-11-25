"""
Settings compartidos entre local.py y production.py.

Secretos vía .env + django-environ (decisión registrada en
Vigia-Roadmap-Desarrollo, vault de Obsidian) — nunca hardcodear
credenciales aquí. Ver .env.example en la raíz del repo para las
variables esperadas.
"""

import hashlib
from datetime import timedelta
from pathlib import Path

import environ
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()

# SHA-256 de claves que fueron públicas (el antiguo valor de .env.example,
# visible en el historial del repo): con ellas cualquiera firma un JWT válido.
CLAVES_COMPROMETIDAS = {"968f8b985b9934bc24827e8fefe319de3024c7c3a822eb7f0e5485ecb4215f3d"}


def validar_secret_key(clave: str) -> None:
    """Se niega a arrancar con una SECRET_KEY pública, corta o predecible."""
    if hashlib.sha256(clave.encode()).hexdigest() in CLAVES_COMPROMETIDAS:
        raise ImproperlyConfigured("DJANGO_SECRET_KEY es una clave pública conocida: genera una nueva.")
    if len(clave) < 50 or len(set(clave)) < 5 or clave.startswith("django-insecure-"):
        raise ImproperlyConfigured(
            "DJANGO_SECRET_KEY es débil: usa get_random_secret_key() (50+ caracteres aleatorios)."
        )


# El build context del Dockerfile es solo backend/ (ver Vigia-UML-Despliegue),
# así que dentro del contenedor no existe un .env físico en BASE_DIR.parent
# — ahí las variables ya llegan inyectadas por `env_file:` de
# docker-compose.yml. read_env() es solo para desarrollo local fuera de
# Docker; por eso se guarda condicionado a que el archivo exista.
_dotenv_path = BASE_DIR.parent / ".env"
if _dotenv_path.exists():
    environ.Env.read_env(_dotenv_path)

SECRET_KEY = env("DJANGO_SECRET_KEY")
validar_secret_key(SECRET_KEY)
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
    "rest_framework_simplejwt.token_blacklist",
    "django_celery_beat",
    "drf_spectacular",
    "drf_spectacular_sidecar",
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
    # Sin valor por defecto: una contraseña conocida no debe servir "por si acaso".
    "default": env.db("DATABASE_URL"),
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
    # Cerrado por defecto: cada vista pública declara AllowAny explícitamente.
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_PAGINATION_CLASS": "config.pagination.PaginacionEstandar",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    # Los endpoints públicos (focos, zonas, históricos) son una API de datos
    # abiertos: el límite por IP evita que una descarga masiva tumbe el
    # servidor. Las vistas con `throttle_classes` propio lo reemplazan.
    "DEFAULT_THROTTLE_CLASSES": ("rest_framework.throttling.AnonRateThrottle",),
    # Los límites por usuario/IP protegen registro, login y creación de
    # reportes. En producción el caché es Redis (límite global, ver
    # production.py); en desarrollo y pruebas, memoria local.
    "DEFAULT_THROTTLE_RATES": {
        # Holgado: un filtro del mapa cuesta ~13 consultas y un salón u oficina
        # comparte la IP (la app no manda la sesión a los endpoints públicos).
        "anon": "20000/hour",
        "registro": "20/hour",
        "login": "60/hour",
        # Cada solicitud manda un correo: el límite evita llenar buzones ajenos
        # y gastar la cuota del SMTP.
        "recuperar": "5/hour",
        "recuperar-confirmar": "30/hour",
        "refresco": "120/hour",
        "reporte": "30/hour",
        "informe": "60/hour",
    },
    # Nginx reemplaza X-Forwarded-For por la IP real del cliente (tomada de
    # CF-Connecting-IP): se confía en exactamente un proxy. Sin esto DRF usaba
    # la cadena completa y cada X-Forwarded-For inventado era una "IP" nueva.
    "NUM_PROXIES": 1,
}

# Documentación OpenAPI (/api/schema/ y /api/docs/).
SPECTACULAR_SETTINGS = {
    "TITLE": "API de Vigía",
    "VERSION": "0.7.0",
    "DESCRIPTION": """
Alertas tempranas de incendios forestales en Colombia. Los endpoints marcados como públicos
no piden sesión y forman una API de **datos abiertos**, con un límite de 20.000 consultas
por hora por IP. Los demás piden un JWT de `/api/auth/token/`.

Los reportes ciudadanos (foto, ubicación y texto) no se publican: son datos personales
(Ley 1581 de 2012) y solo aparecen agregados en las estadísticas.

## Fuentes y licencias

Quien reutilice estos datos debe citar la fuente original. Se entregan "tal cual": los focos en
casi tiempo real no tienen calidad científica y un foco de calor no siempre es un incendio.

| Datos | Fuente | Licencia |
|---|---|---|
| Focos de calor (`/api/focos/`) | NASA FIRMS (LANCE/EOSDIS) | Sin restricciones; citar a LANCE FIRMS (NASA/ESDIS) |
| Focos de calor (`/api/focos/`) | INPE, Programa Queimadas | Acceso público sin licencia publicada; citar al INPE |
| Incendios reportados (`/api/incendios-reportados/`) | UNGRD, datos.gov.co | Datos abiertos (Ley 1712 de 2014) |
| Deforestación (`/api/historico/capa/`) | IDEAM, SMByC | CC BY-SA 4.0 (también las hectáreas por municipio) |
| Límites municipales | geoBoundaries / DANE | CC BY 4.0 |
| Zonas recurrentes (`/api/zonas-recurrentes/`) | Modelo de Vigía sobre NASA FIRMS | Citar Vigía y NASA FIRMS |
""",
    "SERVE_INCLUDE_SCHEMA": False,
    "SWAGGER_UI_DIST": "SIDECAR",
    "SWAGGER_UI_FAVICON_HREF": "SIDECAR",
    "COMPONENT_SPLIT_REQUEST": True,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    # Cada renovación entrega un refresh nuevo y revoca el anterior: un
    # refresh robado deja de servir en cuanto el dueño vuelve a usar la app.
    "REFRESH_TOKEN_LIFETIME": timedelta(days=1),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
}

# Logs a la consola (Twelve-Factor XI): Docker los recoge con `docker compose logs`.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"simple": {"format": "{asctime} {levelname} {name}: {message}", "style": "{"}},
    "handlers": {"consola": {"class": "logging.StreamHandler", "formatter": "simple"}},
    "root": {"handlers": ["consola"], "level": env("LOG_LEVEL", default="INFO")},
    "loggers": {
        # Los 4xx/5xx de Django van como WARNING/ERROR; el detalle de SQL no.
        "django.db.backends": {"level": "WARNING"},
        # El token de Telegram y la MAP_KEY de FIRMS van en la URL: urllib3 la
        # registra en DEBUG, así que nunca baja de WARNING.
        "urllib3": {"level": "WARNING"},
    },
}

# Celery (ver Vigia-UML-Despliegue § Redis "broker")
# Correo (recuperación de contraseña). Sin EMAIL_HOST los correos salen por la
# consola del worker de Celery, que sirve en desarrollo.
EMAIL_HOST = env("EMAIL_HOST", default="")
EMAIL_BACKEND = env(
    "EMAIL_BACKEND",
    default="django.core.mail.backends.smtp.EmailBackend"
    if EMAIL_HOST
    else "django.core.mail.backends.console.EmailBackend",
)
EMAIL_PORT = env.int("EMAIL_PORT", default=587)
EMAIL_USE_TLS = env.bool("EMAIL_USE_TLS", default=True)
EMAIL_HOST_USER = env("EMAIL_HOST_USER", default="")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD", default="")
# `or`: en el .env la clave puede estar vacía.
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="") or "Vigía <no-reply@vigia.foxyyts.qzz.io>"
EMAIL_TIMEOUT = 15

CELERY_BROKER_URL = env("REDIS_URL", default="redis://redis:6379/0")
CELERY_RESULT_BACKEND = env("REDIS_URL", default="redis://redis:6379/0")
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE
# Ninguna tarea se queda colgada ocupando un worker (descargas de FIRMS, INPE
# o la UNGRD sin respuesta). El reentrenamiento tiene su propio límite.
CELERY_TASK_SOFT_TIME_LIMIT = 10 * 60
CELERY_TASK_TIME_LIMIT = 15 * 60

# Credenciales e integraciones externas — ver Vigia-Credenciales-APIs
# (vault de Obsidian) para el proceso de registro de cada una y el
# formato exacto de uso (MAP_KEY en la URL, X-App-Token como header, etc.)
NASA_FIRMS_MAP_KEY = env("NASA_FIRMS_MAP_KEY", default="")
INPE_QUEIMADAS_WFS_URL = env(
    "INPE_QUEIMADAS_WFS_URL",
    default="https://terrabrasilis.dpi.inpe.br/queimadas/geoserver/wfs",
)
UNGRD_SOCRATA_APP_TOKEN = env("UNGRD_SOCRATA_APP_TOKEN", default="")
TELEGRAM_BOT_TOKEN = env("TELEGRAM_BOT_TOKEN", default="")
TELEGRAM_CANAL_PUBLICO_ID = env("TELEGRAM_CANAL_PUBLICO_ID", default="")
TELEGRAM_CANAL_PRIVADO_ID = env("TELEGRAM_CANAL_PRIVADO_ID", default="")
TELEGRAM_CANAL_INTERNO_ID = env("TELEGRAM_CANAL_INTERNO_ID", default="")
