"""
HistoricoDeforestacion — ver Vigia-Modelo-Datos § Satelital/histórico (vault de Obsidian).

Los clientes `ClienteIdeam` / `ClienteUngrd` que la alimentan se agregan
después (ver Vigia-UML-Clases § Servicios).
"""

from django.contrib.gis.db import models

from apps.usuarios.models import Municipio


class HistoricoDeforestacion(models.Model):
    class Fuente(models.TextChoices):
        IDEAM = "IDEAM", "IDEAM"
        UNGRD = "UNGRD", "UNGRD"

    fuente = models.CharField(max_length=10, choices=Fuente.choices)

    # Polígono (no punto): así publican realmente IDEAM y UNGRD.
    area = models.MultiPolygonField(srid=4326)

    anio = models.PositiveSmallIntegerField()

    # Nullable: no todos los registros de las fuentes traen la superficie.
    hectareas_afectadas = models.FloatField(null=True, blank=True)

    municipio = models.ForeignKey(
        Municipio, null=True, blank=True, on_delete=models.SET_NULL, related_name="deforestaciones"
    )

    class Meta:
        verbose_name = "histórico de deforestación"
        verbose_name_plural = "históricos de deforestación"
        indexes = [models.Index(fields=["fuente", "anio"])]

    def __str__(self):
        return f"{self.fuente} {self.anio}"
