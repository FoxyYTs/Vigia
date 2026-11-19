import pytest
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
from rest_framework_simplejwt.tokens import RefreshToken

from apps.usuarios.models import EntidadPublica, Usuario

pytestmark = pytest.mark.django_db

Rol = Usuario.Rol


@pytest.fixture
def otra_entidad(db):
    return EntidadPublica.objects.create(nombre="Corpoamazonia")


@pytest.fixture
def colega(entidad):
    return Usuario.objects.create_user("admin2", email="admin2@x.co", rol=Rol.ADMINISTRADOR, entidad=entidad)


def _patch(cliente, usuario, datos):
    return cliente.patch(f"/api/usuarios/{usuario.pk}/", datos, format="json")


def test_staff_lista_y_filtra_usuarios(api_como, staff, ciudadano, administrador):
    cliente = api_como(staff)
    nombres = [u["username"] for u in cliente.get("/api/usuarios/").data["results"]]
    assert nombres == ["admin1", "ciudadano1", "staff1"]
    assert cliente.get("/api/usuarios/?rol=ciudadano").data["count"] == 1
    r = cliente.get("/api/usuarios/?buscar=ADMIN").data["results"]
    assert [u["username"] for u in r] == ["admin1"] and r[0]["entidad_nombre"] == "Cornare"


def test_administrador_solo_ve_a_los_administradores_de_su_entidad(
    api_como, administrador, colega, ciudadano, staff, otra_entidad
):
    Usuario.objects.create_user("admin3", rol=Rol.ADMINISTRADOR, entidad=otra_entidad)
    r = api_como(administrador).get("/api/usuarios/")
    assert [u["username"] for u in r.data["results"]] == ["admin1", "admin2"]


def test_administrador_sin_entidad_solo_se_ve_a_si_mismo(api_como, staff):
    sin_entidad = Usuario.objects.create_user("admin9", rol=Rol.ADMINISTRADOR)
    Usuario.objects.create_user("admin8", rol=Rol.ADMINISTRADOR)
    r = api_como(sin_entidad).get("/api/usuarios/")
    assert [u["username"] for u in r.data["results"]] == ["admin9"]


def test_staff_promueve_a_administrador_de_una_entidad(api_como, staff, ciudadano, entidad):
    r = _patch(api_como(staff), ciudadano, {"rol": "administrador", "entidad": entidad.pk})
    assert r.status_code == 200 and r.data["entidad_nombre"] == "Cornare"
    ciudadano.refresh_from_db()
    assert ciudadano.rol == Rol.ADMINISTRADOR and ciudadano.entidad == entidad


def test_al_dejar_de_ser_administrador_pierde_la_entidad(api_como, staff, administrador):
    r = _patch(api_como(staff), administrador, {"rol": "ciudadano"})
    assert r.status_code == 200
    administrador.refresh_from_db()
    assert administrador.rol == Rol.CIUDADANO and administrador.entidad is None


def test_desactivar_revoca_las_sesiones(api_como, staff, ciudadano):
    refresco = RefreshToken.for_user(ciudadano)
    assert _patch(api_como(staff), ciudadano, {"is_active": False}).status_code == 200
    ciudadano.refresh_from_db()
    assert not ciudadano.is_active
    assert BlacklistedToken.objects.filter(token__jti=refresco["jti"]).exists()


def test_el_resto_del_perfil_no_se_toca(api_como, staff, ciudadano):
    _patch(api_como(staff), ciudadano, {"username": "otro", "email": "x@y.co", "is_superuser": True})
    ciudadano.refresh_from_db()
    assert ciudadano.username == "ciudadano1" and not ciudadano.is_superuser


def test_rol_invalido(api_como, staff, ciudadano):
    assert _patch(api_como(staff), ciudadano, {"rol": "superadmin"}).status_code == 400


def test_nadie_se_edita_a_si_mismo_ni_a_un_superusuario(api_como, staff):
    raiz = Usuario.objects.create_superuser("raiz", "raiz@x.co", "clave-segura-9")
    cliente = api_como(staff)
    assert _patch(cliente, staff, {"rol": "ciudadano"}).status_code == 403
    assert _patch(cliente, raiz, {"is_active": False}).status_code == 403
    raiz.refresh_from_db()
    assert raiz.is_active


def test_el_administrador_no_edita(api_como, administrador, colega):
    assert _patch(api_como(administrador), colega, {"rol": "staff"}).status_code == 403
    colega.refresh_from_db()
    assert colega.rol == Rol.ADMINISTRADOR


def test_put_no_esta_permitido(api_como, staff, ciudadano):
    assert api_como(staff).put(f"/api/usuarios/{ciudadano.pk}/", {"rol": "staff"}, format="json").status_code == 405


def test_ciudadano_y_anonimo_no_gestionan_permisos(api, api_como, ciudadano):
    assert api.get("/api/usuarios/").status_code == 401
    assert api_como(ciudadano).get("/api/usuarios/").status_code == 403
    assert api_como(ciudadano).get("/api/entidades/").status_code == 403


def test_entidades_ordenadas(api_como, staff, entidad, otra_entidad):
    assert api_como(staff).get("/api/entidades/").data == [
        {"id": entidad.pk, "nombre": "Cornare"},
        {"id": otra_entidad.pk, "nombre": "Corpoamazonia"},
    ]


def test_el_rol_staff_va_con_el_acceso_al_django_admin(api_como, staff, ciudadano):
    otro = Usuario.objects.create_user("staff2", rol=Rol.STAFF, is_staff=True)
    cliente = api_como(staff)
    _patch(cliente, otro, {"rol": "ciudadano"})
    _patch(cliente, ciudadano, {"rol": "staff"})
    otro.refresh_from_db()
    ciudadano.refresh_from_db()
    assert not otro.is_staff and ciudadano.is_staff


def test_cambiar_el_rol_cierra_las_sesiones(api_como, staff, ciudadano):
    refresco = RefreshToken.for_user(ciudadano)
    _patch(api_como(staff), ciudadano, {"rol": "administrador"})
    assert BlacklistedToken.objects.filter(token__jti=refresco["jti"]).exists()


def test_cambiar_solo_la_entidad_no_cierra_las_sesiones(api_como, staff, administrador, otra_entidad):
    refresco = RefreshToken.for_user(administrador)
    _patch(api_como(staff), administrador, {"entidad": otra_entidad.pk})
    assert not BlacklistedToken.objects.filter(token__jti=refresco["jti"]).exists()
