from .base import *  # noqa: F401,F403

DEBUG = False

SECURE_SSL_REDIRECT = False  # TLS lo termina Cloudflare Tunnel, no Django
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# Requerido por Django detrás de un proxy — sin esto, cualquier POST
# (incluido el login del admin) falla con "CSRF verification failed" al
# entrar por el túnel. A diferencia de ALLOWED_HOSTS, necesita el
# esquema completo (https://), no solo el hostname.
CSRF_TRUSTED_ORIGINS = [f"https://{host}" for host in ALLOWED_HOSTS if host not in ("localhost", "127.0.0.1")]
