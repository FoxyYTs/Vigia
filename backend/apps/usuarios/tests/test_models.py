import pytest
from django.db import IntegrityError

from apps.usuarios.models import Municipio, Usuario

pytestmark = pytest.mark.django_db


def test_rol_por_defecto_es_staff():
    assert Usuario.objects.create_user("x", password="clave-segura-9").es_staff()


def test_metodos_de_rol(ciudadano, administrador, staff):
    assert ciudadano.es_ciudadano() and not ciudadano.es_administrador()
    assert administrador.es_administrador() and not administrador.es_staff()
    assert staff.es_staff() and not staff.es_ciudadano()


def test_municipio_unico_por_departamento(municipio):
    with pytest.raises(IntegrityError):
        Municipio.objects.create(nombre="Rionegro", departamento="Antioquia")


def test_mismo_nombre_en_otro_departamento_es_valido(municipio):
    Municipio.objects.create(nombre="Rionegro", departamento="Santander")


def test_entidad_tiene_jurisdiccion_por_municipios(entidad, municipio):
    assert list(entidad.municipios.all()) == [municipio]
    assert entidad.administradores.count() == 0
