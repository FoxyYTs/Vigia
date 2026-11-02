import pytest
from django.core.exceptions import ImproperlyConfigured
from django.core.management.utils import get_random_secret_key

from config.settings.base import validar_secret_key


@pytest.mark.parametrize(
    "clave",
    ["corta", "a" * 60, "django-insecure-" + get_random_secret_key()],
)
def test_rechaza_claves_debiles(clave):
    with pytest.raises(ImproperlyConfigured, match="débil"):
        validar_secret_key(clave)


def test_rechaza_una_clave_publica_conocida(monkeypatch):
    import hashlib

    from config.settings import base

    clave = get_random_secret_key()
    monkeypatch.setattr(base, "CLAVES_COMPROMETIDAS", {hashlib.sha256(clave.encode()).hexdigest()})
    with pytest.raises(ImproperlyConfigured, match="pública"):
        base.validar_secret_key(clave)


def test_acepta_una_clave_aleatoria():
    validar_secret_key(get_random_secret_key())
