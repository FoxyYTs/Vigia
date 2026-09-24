import pytest

from apps.usuarios.models import Usuario

pytestmark = pytest.mark.django_db

REGISTRO = {"username": "maria", "email": "maria@example.com", "password": "una-clave-larga-987"}


def test_registro_crea_un_ciudadano(api, municipio):
    r = api.post("/api/auth/registro/", {**REGISTRO, "municipio_residencia": municipio.pk})
    assert r.status_code == 201
    u = Usuario.objects.get(username="maria")
    assert u.rol == Usuario.Rol.CIUDADANO and u.municipio_residencia == municipio
    assert "password" not in r.data  # nunca se devuelve


def test_registro_ignora_un_rol_enviado_por_el_cliente(api):
    """Escalada de privilegios: nadie se registra como administrador o staff."""
    r = api.post("/api/auth/registro/", {**REGISTRO, "rol": "administrador", "is_staff": True})
    assert r.status_code == 201
    u = Usuario.objects.get(username="maria")
    assert u.rol == Usuario.Rol.CIUDADANO and not u.is_staff and not u.is_superuser


@pytest.mark.parametrize("clave", ["123", "maria1234", "password"])
def test_registro_rechaza_contrasenas_debiles(api, clave):
    r = api.post("/api/auth/registro/", {**REGISTRO, "password": clave})
    assert r.status_code == 400 and "non_field_errors" in r.data
    assert not Usuario.objects.filter(username="maria").exists()


def test_registro_rechaza_correo_repetido(api, ciudadano):
    ciudadano.email = "maria@example.com"
    ciudadano.save()
    r = api.post("/api/auth/registro/", REGISTRO)
    assert r.status_code == 400 and "email" in r.data


def test_registro_tiene_limite_de_intentos(api, monkeypatch):
    from rest_framework.throttling import ScopedRateThrottle

    monkeypatch.setitem(ScopedRateThrottle.THROTTLE_RATES, "registro", "3/hour")
    codigos = [api.post("/api/auth/registro/", {"username": f"u{i}"}).status_code for i in range(5)]
    assert codigos[:3] == [400, 400, 400] and codigos[3:] == [429, 429]


def test_login_devuelve_tokens_con_el_rol(api, administrador):
    import jwt

    r = api.post("/api/auth/token/", {"username": "admin1", "password": "clave-segura-2"})
    assert r.status_code == 200 and {"access", "refresh"} <= set(r.data)
    claims = jwt.decode(r.data["access"], options={"verify_signature": False})
    assert claims["rol"] == "administrador" and claims["username"] == "admin1"


def test_login_con_clave_incorrecta(api, ciudadano):
    assert api.post("/api/auth/token/", {"username": "ciudadano1", "password": "mala"}).status_code == 401


def test_refresh_renueva_el_acceso(api, ciudadano):
    tokens = api.post("/api/auth/token/", {"username": "ciudadano1", "password": "clave-segura-1"}).data
    r = api.post("/api/auth/token/refresh/", {"refresh": tokens["refresh"]})
    assert r.status_code == 200 and "access" in r.data


def test_token_real_autentica_las_peticiones(api, ciudadano):
    tokens = api.post("/api/auth/token/", {"username": "ciudadano1", "password": "clave-segura-1"}).data
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    r = api.get("/api/auth/yo/")
    assert r.status_code == 200 and r.data["username"] == "ciudadano1" and r.data["rol"] == "ciudadano"


def test_yo_exige_sesion(api):
    assert api.get("/api/auth/yo/").status_code == 401


def test_municipios_es_publico_y_filtra_por_departamento(api, municipio):
    from apps.usuarios.models import Municipio

    Municipio.objects.create(nombre="Bello", departamento="Antioquia")
    Municipio.objects.create(nombre="Cali", departamento="Valle del Cauca")
    todos = api.get("/api/municipios/")
    assert todos.status_code == 200 and len(todos.data) == 3
    assert {m["nombre"] for m in api.get("/api/municipios/?departamento=antioquia").data} == {"Rionegro", "Bello"}


def test_municipios_no_se_modifica_por_la_api(api_como, staff):
    assert api_como(staff).post("/api/municipios/", {"nombre": "X", "departamento": "Y"}).status_code == 405
