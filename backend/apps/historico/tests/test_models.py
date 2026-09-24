import pytest
from django.contrib.gis.geos import MultiPolygon, Polygon

from apps.historico.models import HistoricoDeforestacion

pytestmark = pytest.mark.django_db


def _multipoligono():
    return MultiPolygon(Polygon(((0, 0), (0, 1), (1, 1), (1, 0), (0, 0))), srid=4326)


def test_crea_registro_con_poligono(municipio):
    h = HistoricoDeforestacion.objects.create(
        fuente=HistoricoDeforestacion.Fuente.IDEAM,
        area=_multipoligono(),
        anio=2023,
        hectareas_afectadas=12.5,
        municipio=municipio,
    )
    assert str(h) == "IDEAM 2023"
    assert h.area.geom_type == "MultiPolygon"


def test_hectareas_y_municipio_son_opcionales():
    h = HistoricoDeforestacion.objects.create(
        fuente=HistoricoDeforestacion.Fuente.UNGRD, area=_multipoligono(), anio=2022
    )
    assert h.hectareas_afectadas is None and h.municipio is None
