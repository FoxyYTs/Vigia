from .base import *  # noqa: F401,F403

DEBUG = False

SECURE_SSL_REDIRECT = False  # TLS lo termina Cloudflare Tunnel, no Django
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
SECURE_CONTENT_TYPE_NOSNIFF = True

# Límites de intentos compartidos entre los procesos de gunicorn y que
# sobreviven a reinicios (base 1 de Redis; la 0 es de Celery).
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": env("REDIS_CACHE_URL", default="redis://redis:6379/1"),  # noqa: F405
    }
}

# Sin la API navegable de DRF en producción: solo JSON.
REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"] = ("rest_framework.renderers.JSONRenderer",)  # noqa: F405
CSRF_COOKIE_SECURE = True

# Requerido por Django detrás de un proxy — sin esto, cualquier POST
# (incluido el login del admin) falla con "CSRF verification failed" al
# entrar por el túnel. A diferencia de ALLOWED_HOSTS, necesita el
# esquema completo (https://), no solo el hostname.
# ALLOWED_HOSTS viene de `from .base import *`.
CSRF_TRUSTED_ORIGINS = [f"https://{host}" for host in ALLOWED_HOSTS if host not in ("localhost", "127.0.0.1")]  # noqa: F405
