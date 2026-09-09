from .base import *  # noqa: F401,F403

DEBUG = False

SECURE_SSL_REDIRECT = False  # TLS lo termina Cloudflare Tunnel, no Django
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
