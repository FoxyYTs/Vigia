import pytest
from django.contrib.gis.geos import Point
from django.core.management import call_command

from apps.usuarios.models import EntidadPublica, Municipio
from conftest import RIONEGRO

pytestmark = pytest.mark.django_db


@pytest.fixture(scope="module")
def cargados(django_db_setup, django_db_blocker):
    # Cargar 1.122 polígonos una sola vez para todo el módulo.
    with django_db_blocker.unblock():
        call_command("cargar_municipios", ejecutar=True)
    yield
    with django_db_blocker.unblock():
        Municipio.objects.all().delete()
        EntidadPublica.objects.all().delete()


def test_simulacro_no_guarda_nada():
    antes = Municipio.objects.count()
    call_command("cargar_municipios")
    assert Municipio.objects.count() == antes


def test_carga_todos_con_codigo_y_poligono(cargados):
    assert Municipio.objects.count() == 1122
    assert Municipio.objects.filter(codigo_dane__isnull=True).count() == 0
    # Solo Nuevo Belén de Bajirá, posterior a la fuente de polígonos.
    assert list(Municipio.objects.filter(geom__isnull=True).values_list("codigo_dane", flat=True)) == ["27493"]


def test_un_punto_cae_en_su_municipio(cargados):
    m = Municipio.objects.get(geom__contains=RIONEGRO)
    assert (m.nombre, m.departamento, m.codigo_dane) == ("Rionegro", "Antioquia", "05615")


def test_municipios_con_el_mismo_nombre_quedan_en_su_departamento(cargados):
    colon_putumayo = Point(-76.9737, 1.1903, srid=4326)  # cabecera de Colón, Putumayo
    assert Municipio.objects.get(geom__contains=colon_putumayo).codigo_dane == "86219"


def test_cornare_tiene_sus_26_municipios(cargados):
    cornare = EntidadPublica.objects.get(nombre="Cornare")
    assert cornare.municipios.count() == 26
    assert cornare.municipios.filter(nombre="Rionegro").exists()
