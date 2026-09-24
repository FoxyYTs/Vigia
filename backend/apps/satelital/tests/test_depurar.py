from datetime import datetime, timezone

import pytest
from django.contrib.gis.geos import Point
from django.core.management import call_command

from apps.satelital.models import FocoIncendio

pytestmark = pytest.mark.django_db

FECHA = datetime(2026, 9, 1, tzinfo=timezone.utc)


def _foco(lon, lat, fuente=FocoIncendio.Fuente.NASA_FIRMS):
    return FocoIncendio.objects.create(
        fuente=fuente, ubicacion=Point(lon, lat, srid=4326), fecha_hora=FECHA
    )


@pytest.fixture
def focos():
    return {
        "rionegro": _foco(-75.37, 6.15),
        "caracas": _foco(-66.90, 10.48),
        "quito": _foco(-78.47, -0.18),
        "inpe_afuera": _foco(-66.90, 10.48, FocoIncendio.Fuente.INPE_QUEIMADAS),
    }


def test_simulacro_no_borra_nada(focos, capsys):
    call_command("depurar_focos_fuera_de_colombia")
    assert FocoIncendio.objects.count() == 4
    assert "Fuera de Colombia (NASA FIRMS): 2" in capsys.readouterr().out


def test_ejecutar_borra_solo_los_de_firms_fuera_de_colombia(focos):
    call_command("depurar_focos_fuera_de_colombia", "--ejecutar")
    restantes = set(FocoIncendio.objects.values_list("id", flat=True))
    # INPE ya llega filtrado por país: el comando no toca esa fuente.
    assert restantes == {focos["rionegro"].id, focos["inpe_afuera"].id}


def test_es_idempotente(focos):
    call_command("depurar_focos_fuera_de_colombia", "--ejecutar")
    call_command("depurar_focos_fuera_de_colombia", "--ejecutar")
    assert FocoIncendio.objects.count() == 2
