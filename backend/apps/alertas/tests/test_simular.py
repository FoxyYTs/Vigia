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


def test_limpiar_no_toca_a_un_usuario_real_con_el_prefijo_demo(crear_reporte):
    impostor = Usuario.objects.create_user(
        "demo_sim_impostor", password="clave-segura-9", rol=Usuario.Rol.CIUDADANO
    )
    suyo = crear_reporte(ciudadano=impostor)
    call_command("simular_alertas", pausa=0)
    # Un reporte real corrobora la alerta de acumulación de la demo.
    acumulacion = Alerta.objects.get(tipo_disparador=Alerta.TipoDisparador.ACUMULACION_REPORTES)
    acumulacion.reportes.add(suyo)

    call_command("simular_alertas", limpiar=True)
    assert Usuario.objects.filter(pk=impostor.pk).exists()
    assert ReporteCiudadano.objects.filter(pk=suyo.pk).exists()
    assert list(Alerta.objects.all()) == [acumulacion]
    assert list(acumulacion.reportes.all()) == [suyo]


def test_con_telegram_configurado_exige_forzar(settings):
    from django.core.management import CommandError

    settings.TELEGRAM_BOT_TOKEN = "123:abc"
    with pytest.raises(CommandError, match="--forzar"):
        call_command("simular_alertas", pausa=0)
    assert not Alerta.objects.exists()
