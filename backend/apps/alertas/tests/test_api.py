import pytest

from apps.alertas.models import Alerta

pytestmark = pytest.mark.django_db


@pytest.fixture
def alerta(foco, municipio):
    return Alerta.objects.create(
        tipo_disparador=Alerta.TipoDisparador.DETECCION_SATELITAL,
        foco=foco,
        ubicacion=foco.ubicacion,
        municipio=municipio,
    )


def test_alertas_exige_sesion(api, alerta):
    assert api.get("/api/alertas/").status_code == 401


@pytest.mark.parametrize("quien", ["ciudadano", "administrador", "staff"])
def test_cualquier_usuario_autenticado_las_consulta(api_como, request, alerta, quien):
    r = api_como(request.getfixturevalue(quien)).get("/api/alertas/")
    assert r.status_code == 200
    a = r.data["results"][0]
    assert a["tipo_disparador"] == "deteccion_satelital" and a["municipio"] == "Rionegro, Antioquia"
    assert a["latitud"] == pytest.approx(6.1552)


def test_filtro_por_tipo(api_como, ciudadano, alerta, reporte):
    Alerta.objects.create(tipo_disparador="validacion_manual", ubicacion=reporte.ubicacion_incendio)
    r = api_como(ciudadano).get("/api/alertas/?tipo=validacion_manual")
    assert [a["tipo_disparador"] for a in r.data["results"]] == ["validacion_manual"]


def test_alertas_no_se_crean_por_la_api(api_como, administrador):
    assert api_como(administrador).post("/api/alertas/", {}).status_code == 405
