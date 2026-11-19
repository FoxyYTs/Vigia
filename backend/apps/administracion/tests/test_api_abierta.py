"""API de datos abiertos: documentación OpenAPI y límite por IP para anónimos."""

from unittest.mock import patch

import pytest
from django.core.management import call_command
from rest_framework.throttling import AnonRateThrottle

pytestmark = pytest.mark.django_db


def test_el_esquema_documenta_los_endpoints_y_las_fuentes(api):
    r = api.get("/api/schema/?format=json")
    assert r.status_code == 200
    esquema = r.json()
    assert {"/api/focos/", "/api/incendios-reportados/", "/api/zonas-recurrentes/"} <= set(esquema["paths"])
    for fuente in ("NASA FIRMS", "Programa Queimadas", "UNGRD", "IDEAM", "CC BY-SA 4.0", "tal cual"):
        assert fuente in esquema["info"]["description"]


def test_el_esquema_es_valido_y_sin_avisos(tmp_path):
    # Un endpoint nuevo sin tipos (vista de función sin @extend_schema) rompe esta prueba.
    call_command("spectacular", "--validate", "--fail-on-warn", "--file", str(tmp_path / "esquema.yml"))


def test_swagger_sin_scripts_en_linea_ni_cdn(api):
    r = api.get("/api/docs/")
    assert r.status_code == 200
    html = r.content.decode()
    # La CSP de Nginx solo admite scripts propios.
    assert "cdn.jsdelivr.net" not in html and "<script>" not in html
    assert "/static/drf_spectacular_sidecar/swagger-ui-dist/swagger-ui-bundle.js" in html


def test_los_anonimos_tienen_un_limite_por_ip(api, api_como, ciudadano):
    with patch.object(AnonRateThrottle, "get_rate", return_value="2/hour"):
        assert [api.get("/api/focos/").status_code for _ in range(3)] == [200, 200, 429]
        # Con sesión no cuenta el límite de anónimos.
        assert api_como(ciudadano).get("/api/focos/").status_code == 200
