import pytest

from apps.reportes.models import ReporteCiudadano

pytestmark = pytest.mark.django_db


def _datos(imagen, **extra):
    return {
        "foto": imagen,
        "descripcion": "Humo visible en la ladera",
        "latitud_usuario": 6.20,
        "longitud_usuario": -75.40,
        "latitud_incendio": 6.15,
        "longitud_incendio": -75.37,
        **extra,
    }


def test_ciudadano_crea_un_reporte(api_como, ciudadano, imagen_png):
    r = api_como(ciudadano).post("/api/reportes/", _datos(imagen_png), format="multipart")
    assert r.status_code == 201
    assert r.data["estado"] == "pendiente" and r.data["ciudadano"] == "ciudadano1"
    assert r.data["ubicacion_incendio"] == {"latitud": pytest.approx(6.15), "longitud": pytest.approx(-75.37)}
    assert r.data["distancia_reportada_km"] > 0
    assert ReporteCiudadano.objects.get().ciudadano == ciudadano


def test_el_ciudadano_no_puede_fijar_estado_ni_validador(api_como, ciudadano, administrador, imagen_png):
    r = api_como(ciudadano).post(
        "/api/reportes/",
        _datos(imagen_png, estado="validado", validado_por=administrador.pk),
        format="multipart",
    )
    assert r.status_code == 201
    reporte = ReporteCiudadano.objects.get()
    assert reporte.estado == "pendiente" and reporte.validado_por is None


def test_la_foto_es_obligatoria(api_como, ciudadano, imagen_png):
    datos = _datos(imagen_png)
    del datos["foto"]
    r = api_como(ciudadano).post("/api/reportes/", datos, format="multipart")
    assert r.status_code == 400 and "foto" in r.data


def test_un_archivo_que_no_es_imagen_se_rechaza(api_como, ciudadano):
    from django.core.files.uploadedfile import SimpleUploadedFile

    falso = SimpleUploadedFile("virus.png", b"no soy una imagen", content_type="image/png")
    r = api_como(ciudadano).post("/api/reportes/", _datos(falso), format="multipart")
    assert r.status_code == 400 and "foto" in r.data


def test_foto_demasiado_grande(api_como, ciudadano, imagen_png, monkeypatch):
    monkeypatch.setattr("apps.reportes.serializers.TAMANO_MAXIMO_FOTO", 10)
    r = api_como(ciudadano).post("/api/reportes/", _datos(imagen_png), format="multipart")
    assert r.status_code == 400 and "5 MB" in str(r.data["foto"])


@pytest.mark.parametrize("campo,valor", [("latitud_incendio", 91), ("longitud_usuario", -181)])
def test_coordenadas_fuera_de_rango(api_como, ciudadano, imagen_png, campo, valor):
    r = api_como(ciudadano).post("/api/reportes/", _datos(imagen_png, **{campo: valor}), format="multipart")
    assert r.status_code == 400 and campo in r.data


def test_anonimo_no_puede_reportar(api, imagen_png):
    assert api.post("/api/reportes/", _datos(imagen_png), format="multipart").status_code == 401


@pytest.mark.parametrize("quien", ["administrador", "staff"])
def test_solo_un_ciudadano_crea_reportes(api_como, request, imagen_png, quien):
    r = api_como(request.getfixturevalue(quien)).post("/api/reportes/", _datos(imagen_png), format="multipart")
    assert r.status_code == 403


def test_ciudadano_solo_ve_sus_reportes(api_como, ciudadano, crear_reporte, municipio):
    from apps.usuarios.models import Usuario

    propio = crear_reporte()
    otro = Usuario.objects.create_user("otro", password="clave-segura-4", rol=Usuario.Rol.CIUDADANO)
    ajeno = crear_reporte(ciudadano=otro)

    cliente = api_como(ciudadano)
    assert {x["id"] for x in cliente.get("/api/reportes/").data["results"]} == {propio.id}
    assert cliente.get(f"/api/reportes/{ajeno.id}/").status_code == 404  # ni siquiera confirma que existe


def test_administrador_ve_todos_y_filtra_por_estado(api_como, administrador, crear_reporte):
    pendiente, resuelto = crear_reporte(), crear_reporte()
    resuelto.validar(administrador)
    cliente = api_como(administrador)
    assert len(cliente.get("/api/reportes/").data["results"]) == 2
    assert [x["id"] for x in cliente.get("/api/reportes/?estado=pendiente").data["results"]] == [pendiente.id]


def test_staff_consulta_todos_los_reportes_en_solo_lectura(api_como, staff, crear_reporte):
    reporte = crear_reporte()
    cliente = api_como(staff)
    assert [x["id"] for x in cliente.get("/api/reportes/").data["results"]] == [reporte.id]
    assert cliente.get(f"/api/reportes/{reporte.id}/").status_code == 200


def test_staff_no_puede_validar_ni_rechazar(api_como, staff, reporte):
    cliente = api_como(staff)
    assert cliente.post(f"/api/reportes/{reporte.id}/validar/").status_code == 403
    assert cliente.post(f"/api/reportes/{reporte.id}/rechazar/").status_code == 403
    reporte.refresh_from_db()
    assert reporte.estado == "pendiente"


def test_administrador_valida_un_reporte(api_como, administrador, reporte):
    r = api_como(administrador).post(f"/api/reportes/{reporte.id}/validar/")
    assert r.status_code == 200 and r.data["estado"] == "validado"
    reporte.refresh_from_db()
    assert reporte.validado_por == administrador and reporte.fecha_validacion is not None


def test_administrador_rechaza_un_reporte(api_como, administrador, reporte):
    r = api_como(administrador).post(f"/api/reportes/{reporte.id}/rechazar/")
    assert r.status_code == 200 and r.data["estado"] == "rechazado"


def test_no_se_resuelve_dos_veces(api_como, administrador, reporte):
    cliente = api_como(administrador)
    cliente.post(f"/api/reportes/{reporte.id}/validar/")
    assert cliente.post(f"/api/reportes/{reporte.id}/rechazar/").status_code == 409


def test_un_ciudadano_no_puede_validar_ni_siquiera_el_suyo(api_como, ciudadano, reporte):
    assert api_como(ciudadano).post(f"/api/reportes/{reporte.id}/validar/").status_code == 403
    reporte.refresh_from_db()
    assert reporte.estado == "pendiente"
