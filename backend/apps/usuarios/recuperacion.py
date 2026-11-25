"""Recuperación de contraseña con un código de 6 dígitos enviado por correo.

El código no se guarda: en la caché (Redis en producción) queda su HMAC con
SECRET_KEY, vigente 15 minutos. Límites por cuenta, que no dependen de la IP:
5 intentos por código y 3 códigos por hora, o sea, 15 intentos por hora como
máximo contra un millón de combinaciones."""

import hashlib
import hmac
import secrets

from django.conf import settings
from django.core.cache import cache

VIGENCIA_SEGUNDOS = 15 * 60
INTENTOS_MAXIMOS = 5
CODIGOS_POR_HORA = 3


def _claves(usuario) -> tuple[str, str, str]:
    base = f"recuperar-contrasena:{usuario.pk}"
    return base, f"{base}:intentos", f"{base}:emitidos"


def _huella(codigo: str) -> str:
    return hmac.new(settings.SECRET_KEY.encode(), codigo.encode(), hashlib.sha256).hexdigest()


def generar_codigo(usuario) -> str | None:
    """Crea un código nuevo (el anterior deja de servir), o None si la cuenta
    ya pidió CODIGOS_POR_HORA en la última hora."""
    clave_huella, clave_intentos, clave_emitidos = _claves(usuario)
    cache.add(clave_emitidos, 0, 60 * 60)
    if cache.incr(clave_emitidos) > CODIGOS_POR_HORA:
        return None
    codigo = f"{secrets.randbelow(10**6):06d}"
    cache.set_many({clave_huella: _huella(codigo), clave_intentos: 0}, VIGENCIA_SEGUNDOS)
    return codigo


def usar_codigo(usuario, codigo: str) -> bool:
    """True si el código es correcto (y lo consume)."""
    clave_huella, clave_intentos, _ = _claves(usuario)
    try:
        # incr es atómico (INCR en Redis): el intento se cuenta antes de
        # comparar, así peticiones en paralelo no pasan del máximo.
        intento = cache.incr(clave_intentos)
    except ValueError:  # sin código vigente
        return False
    huella = cache.get(clave_huella)
    if huella is None or intento > INTENTOS_MAXIMOS:
        cache.delete_many([clave_huella, clave_intentos])
        return False
    if not hmac.compare_digest(huella, _huella(codigo)):
        return False
    cache.delete_many([clave_huella, clave_intentos])
    return True
