import csv
import io
from datetime import datetime, UTC

import pytest
from django.contrib.gis.geos import MultiPolygon, Point, Polygon
from openpyxl import load_workbook

from apps.administracion.exportador import ExportadorDatos
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from conftest import RIONEGRO

pytestmark = pytest.mark.django_db

PERIODO = "desde=2026-09-01&hasta=2026-09-30"
CUCUTA = Point(-72.50, 7.89, srid=4326)


@pytest.fixture
def datos(municipio, crear_reporte):
    municipio.geom = MultiPolygon(Polygon.from_bbox((-75.5, 6.0, -75.2, 6.3)), srid=4326)
    municipio.save()
    for punto in (RIONEGRO, CUCUTA):
        FocoIncendio.objects.create(
            fuente=FocoIncendio.Fuente.NASA_FIRMS, ubicacion=punto, satelite="N20",
            fecha_hora=datetime(2026, 9, 2, 15, 0, tzinfo=UTC), confianza="n",
        )
    crear_reporte(descripcion='=HYPERLINK("http://malo")')
    ReporteCiudadano.objects.update(fecha_creacion=datetime(2026, 9, 10, 15, 0, tzinfo=UTC))


def _csv(respuesta):
    return list(csv.reader(io.StringIO(respuesta.content.decode("utf-8-sig"))))


def test_csv_de_focos_con_municipio(api_como, staff, datos):
    r = api_como(staff).get(f"/api/informes/?formato=csv&conjunto=focos&{PERIODO}")
    assert r.status_code == 200
    assert r["Content-Type"].startswith("text/csv")
    assert r["Content-Disposition"] == 'attachment; filename="vigia-focos-2026-09-01_2026-09-30.csv"'
    filas = _csv(r)
    assert filas[0][:3] == ["fecha_hora", "fuente", "satelite"]
    # 15:00 UTC = 10:00 en Colombia.
    assert filas[1][0] == "2026-09-02 10:00" and filas[1][1] == "NASA FIRMS"
    assert sorted(f[7] for f in filas[1:]) == ["", "Rionegro"]


def test_csv_de_reportes_neutraliza_formulas_y_omite_al_ciudadano(api_como, staff, datos):
    filas = _csv(api_como(staff).get(f"/api/informes/?formato=csv&conjunto=reportes&{PERIODO}"))
    assert "ciudadano" not in filas[0]
    assert filas[1][-1] == '\'=HYPERLINK("http://malo")'


def test_excel_tiene_resumen_y_una_hoja_por_conjunto(api_como, staff, datos):
    r = api_como(staff).get(f"/api/informes/?formato=xlsx&{PERIODO}")
    assert r.status_code == 200
    libro = load_workbook(io.BytesIO(r.content))
    assert libro.sheetnames == ["Resumen", "Focos", "Alertas", "Reportes"]
    resumen = [fila for fila in libro["Resumen"].iter_rows(values_only=True)]
    assert ("Detecciones satelitales", 2) in resumen
    assert libro["Focos"].max_row == 3 and libro["Reportes"].max_row == 2
    assert libro["Reportes"]["G2"].value.startswith("'=")


def test_pdf(api_como, staff, datos):
    r = api_como(staff).get(f"/api/informes/?formato=pdf&{PERIODO}")
    assert r.status_code == 200
    assert r["Content-Type"] == "application/pdf" and r.content.startswith(b"%PDF")


def test_el_administrador_exporta_solo_su_jurisdiccion(api_como, administrador, datos):
    filas = _csv(api_como(administrador).get(f"/api/informes/?formato=csv&conjunto=focos&{PERIODO}"))
    assert [f[7] for f in filas[1:]] == ["Rionegro"]


def test_periodo_sin_datos_tambien_genera_los_tres_formatos(municipio):
    exportador = ExportadorDatos(datetime(2020, 1, 1).date(), datetime(2020, 1, 31).date())
    assert exportador.exportar_csv("alertas").decode("utf-8-sig").startswith("id,fecha_creacion")
    assert exportador.exportar_excel() and exportador.exportar_pdf().startswith(b"%PDF")


@pytest.mark.parametrize(
    "consulta",
    [
        "formato=docx",
        "formato=csv&conjunto=usuarios",
        PERIODO,
        "formato=pdf&desde=2026-09-30&hasta=2026-09-01",
        "formato=xlsx&desde=2026-01-01&hasta=2026-09-30",
    ],
)
def test_parametros_invalidos(api_como, staff, consulta):
    assert api_como(staff).get(f"/api/informes/?{consulta}").status_code == 400


def test_ciudadano_y_anonimo_no_exportan(api, api_como, ciudadano):
    assert api.get(f"/api/informes/?formato=pdf&{PERIODO}").status_code == 401
    assert api_como(ciudadano).get(f"/api/informes/?formato=pdf&{PERIODO}").status_code == 403


def test_el_pdf_admite_un_anio(api_como, staff):
    assert api_como(staff).get("/api/informes/?formato=pdf&desde=2025-10-01&hasta=2026-09-30").status_code == 200
