import pytest

from apps.satelital.geografia import esta_en_colombia


@pytest.mark.parametrize(
    "nombre,lon,lat",
    [
        ("Bogotá", -74.07, 4.71),
        ("Rionegro", -75.37, 6.15),
        ("Cúcuta (frontera)", -72.51, 7.89),
        ("Leticia (Amazonas)", -69.94, -4.21),
        ("Riohacha (costa)", -72.91, 11.54),
        ("Tumaco (Pacífico)", -78.76, 1.80),
    ],
)
def test_puntos_dentro_de_colombia(nombre, lon, lat):
    assert esta_en_colombia(lon, lat), nombre


@pytest.mark.parametrize(
    "nombre,lon,lat",
    [
        ("Caracas", -66.90, 10.48),
        ("Llanos venezolanos", -67.50, 7.80),
        ("Maracaibo", -71.64, 10.64),
        ("Quito", -78.47, -0.18),
        ("Manaos (Brasil)", -60.02, -3.12),
        ("Ciudad de Panamá", -79.52, 8.98),
        ("Mar Caribe abierto", -75.00, 14.00),
        ("Océano Pacífico abierto", -80.00, 3.00),
    ],
)
def test_puntos_fuera_de_colombia(nombre, lon, lat):
    assert not esta_en_colombia(lon, lat), nombre
