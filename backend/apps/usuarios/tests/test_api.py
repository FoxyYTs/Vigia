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


def test_geometria_de_municipios_es_geojson_simplificado(api, municipio):
    from django.contrib.gis.geos import MultiPolygon, Polygon

    # Un polígono con 200 vértices casi alineados: la simplificación debe reducirlos.
    puntos = [(-75.5 + i * 0.001, 6.0 + (i % 2) * 0.0001) for i in range(200)]
    puntos += [(-75.3, 6.3), (-75.5, 6.3), (-75.5, 6.0)]
    municipio.codigo_dane, municipio.geom = "05615", MultiPolygon(Polygon(puntos), srid=4326)
    municipio.save()
    from apps.usuarios.models import Municipio

    Municipio.objects.create(nombre="Sin polígono", departamento="Chocó", codigo_dane="27493")

    r = api.get("/api/municipios/geometria/").data
    assert r["type"] == "FeatureCollection" and len(r["features"]) == 1
    f = r["features"][0]
    assert f["properties"] == {"codigo_dane": "05615", "nombre": "Rionegro", "departamento": "Antioquia"}
    anillo = f["geometry"]["coordinates"][0][0]
    assert f["geometry"]["type"] == "MultiPolygon" and len(anillo) < 20
    assert api.get("/api/municipios/").data[0]["codigo_dane"] == "05615"


def test_refresh_rota_y_logout_revoca(api, ciudadano):
    tokens = api.post("/api/auth/token/", {"username": "ciudadano1", "password": "clave-segura-1"}).data
    renovado = api.post("/api/auth/token/refresh/", {"refresh": tokens["refresh"]})
    assert renovado.status_code == 200 and renovado.data["refresh"] != tokens["refresh"]
    # El refresh viejo quedó revocado al rotar.
    assert api.post("/api/auth/token/refresh/", {"refresh": tokens["refresh"]}).status_code == 401

    assert api.post("/api/auth/logout/", {"refresh": renovado.data["refresh"]}).status_code == 200
    assert api.post("/api/auth/token/refresh/", {"refresh": renovado.data["refresh"]}).status_code == 401


def test_login_no_se_cachea(api, ciudadano):
    r = api.post("/api/auth/token/", {"username": "ciudadano1", "password": "clave-segura-1"})
    assert "no-cache" in r["Cache-Control"] or "no-store" in r["Cache-Control"]


def test_x_forwarded_for_inventado_no_evade_el_limite(api, settings):
    settings.REST_FRAMEWORK = {**settings.REST_FRAMEWORK, "DEFAULT_THROTTLE_RATES": {
        **settings.REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"], "login": "2/hour"}}
    from rest_framework.settings import api_settings
    from rest_framework.throttling import ScopedRateThrottle

    api_settings.reload()
    ScopedRateThrottle.THROTTLE_RATES = api_settings.DEFAULT_THROTTLE_RATES
    try:
        codigos = [
            # Nginx reescribe X-Forwarded-For con la IP real: aquí es siempre la misma.
            api.post("/api/auth/token/", {"username": "x", "password": "y"},
                     HTTP_X_FORWARDED_FOR=f"10.0.0.{i}, 203.0.113.7").status_code
            for i in range(3)
        ]
    finally:
        api_settings.reload()
        ScopedRateThrottle.THROTTLE_RATES = api_settings.DEFAULT_THROTTLE_RATES
    assert codigos[-1] == 429
