"""
FocoIncendio — ver Vigia-Modelo-Datos § Satelital (vault de Obsidian).

Una sola tabla acumula tiempo real (Celery Beat cada 3h) e histórico masivo
(archivo histórico de NASA FIRMS) — "histórico" vs "activo" es un filtro
por fecha, no dos esquemas. NASA FIRMS e INPE QUEIMADAS comparten tabla
con el campo `fuente`.

CORRECCIÓN 09-sep-2026 (probado contra la API real, no de memoria): el
diseño original tenía `confianza` como `float`, pero VIIRS_NOAA20_NRT
(la fuente que usa Vigía) entrega un valor categórico de una letra
('l'/'n'/'h' = low/nominal/high), no un porcentaje. MODIS sí usa 0-100
numérico — por eso el campo queda como CharField genérico, interpretado
según `fuente`, en vez de FloatField. Ver Vigia-Modelo-Datos § Pendiente.
"""

from django.contrib.gis.db import models


class FocoIncendio(models.Model):
    class Fuente(models.TextChoices):
        NASA_FIRMS = "NASA_FIRMS", "NASA FIRMS"
        INPE_QUEIMADAS = "INPE_QUEIMADAS", "INPE QUEIMADAS"

    fuente = models.CharField(max_length=20, choices=Fuente.choices)

    # geography=True (no geometry) para que ST_DWithin calcule en metros/km
    # directamente — necesario para el radio de 10km del motor de alertas.
    ubicacion = models.PointField(geography=True, srid=4326)

    fecha_hora = models.DateTimeField(help_text="Momento de la detección satelital (UTC).")

    # Categórico ('l'/'n'/'h' en VIIRS) o numérico como texto (MODIS,
    # 0-100) según `fuente` — ver docstring del módulo.
    confianza = models.CharField(max_length=10, blank=True, default="")

    # Fire Radiative Power (FRP), en megawatts — mismo campo y unidad en
    # VIIRS y MODIS, a diferencia de confianza.
    brillo_frp = models.FloatField(null=True, blank=True)

    satelite = models.CharField(max_length=20, blank=True, default="")

    creado_en = models.DateTimeField(auto_now_add=True, help_text="Momento de ingesta al sistema.")

    class Meta:
        indexes = [
            models.Index(fields=["fuente", "fecha_hora"]),
        ]
        constraints = [
            # Dedup natural: la misma detección reportada dos veces por la
            # API (mismo punto, misma fuente, mismo instante) no debe
            # duplicarse en la tabla.
            models.UniqueConstraint(
                fields=["fuente", "ubicacion", "fecha_hora"],
                name="foco_incendio_unico_por_fuente_ubicacion_fecha",
            ),
        ]

    def __str__(self):
        return f"{self.fuente} @ {self.fecha_hora:%Y-%m-%d %H:%M} ({self.ubicacion.y:.4f}, {self.ubicacion.x:.4f})"
