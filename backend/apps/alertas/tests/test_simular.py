import pytest
from django.core.management import call_command

from apps.alertas.models import Alerta
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Usuario

pytestmark = pytest.mark.django_db


def test_simulacion_dispara_las_4_condiciones_y_se_limpia():
    call_command("simular_alertas", pausa=0)
    assert set(Alerta.objects.values_list("tipo_disparador", flat=True)) == set(Alerta.TipoDisparador.values)
    assert Alerta.objects.count() == 4

    call_command("simular_alertas", limpiar=True)
    assert not Alerta.objects.exists()
    assert not ReporteCiudadano.objects.exists() and not FocoIncendio.objects.exists()
    assert not Usuario.objects.filter(username__startswith="demo_sim_").exists()
