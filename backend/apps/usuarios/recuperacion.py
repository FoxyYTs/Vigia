"""Recuperación de contraseña con un código de 6 dígitos enviado por correo.

El código no se guarda: en la caché (Redis en producción) queda su HMAC con
SECRET_KEY, vigente 15 minutos y con 5 intentos como máximo."""

import hashlib
import hmac
import secrets
import time

from django.conf import settings
from django.core.cache import cache

VIGENCIA_SEGUNDOS = 15 * 60
INTENTOS_MAXIMOS = 5


def _clave(usuario) -> str:
    return f"recuperar-contrasena:{usuario.pk}"


def _huella(codigo: str) -> str:
    return hmac.new(settings.SECRET_KEY.encode(), codigo.encode(), hashlib.sha256).hexdigest()


def generar_codigo(usuario) -> str:
    """Crea un código nuevo; el anterior, si había, deja de servir."""
    codigo = f"{secrets.randbelow(10**6):06d}"
    datos = {"huella": _huella(codigo), "intentos": 0, "vence": time.time() + VIGENCIA_SEGUNDOS}
    cache.set(_clave(usuario), datos, VIGENCIA_SEGUNDOS)
    return codigo


def usar_codigo(usuario, codigo: str) -> bool:
    """True si el código es correcto (y lo consume). Cada fallo gasta un intento."""
    datos = cache.get(_clave(usuario))
    if not datos:
        return False
    if hmac.compare_digest(datos["huella"], _huella(codigo)):
        cache.delete(_clave(usuario))
        return True
    datos["intentos"] += 1
    restante = int(datos["vence"] - time.time())
    if datos["intentos"] >= INTENTOS_MAXIMOS or restante <= 0:
        cache.delete(_clave(usuario))
    else:
        cache.set(_clave(usuario), datos, restante)
    return False
