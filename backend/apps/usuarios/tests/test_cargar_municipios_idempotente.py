import pytest
from django.core.management import call_command

from apps.usuarios.models import Municipio

pytestmark = pytest.mark.django_db


def test_repetir_la_carga_no_duplica_y_completa_filas_manuales(municipio, ciudadano):
    # `municipio` es "Rionegro, Antioquia" creado a mano, sin código, y un ciudadano vive ahí.
    call_command("cargar_municipios", ejecutar=True)
    call_command("cargar_municipios", ejecutar=True)

    assert Municipio.objects.count() == 1122
    municipio.refresh_from_db()
    assert municipio.codigo_dane == "05615" and municipio.geom is not None
    ciudadano.refresh_from_db()
    assert ciudadano.municipio_residencia == municipio
