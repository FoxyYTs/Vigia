"""
HistoricoDeforestacion e IncendioReportado — ver Vigia-Modelo-Datos §
Satelital/histórico y Vigia-Plan-I1c-Historicos (vault de Obsidian).

Cambio de diseño del 1-nov-2026: la UNGRD no publica deforestación sino
incendios reportados (con fecha y municipio), así que tiene su propio modelo
y HistoricoDeforestacion queda solo para el IDEAM.
"""

from django.contrib.gis.db import models

from apps.usuarios.models import Municipio


class HistoricoDeforestacion(models.Model):
    class Fuente(models.TextChoices):
        IDEAM = "IDEAM", "IDEAM"

    fuente = models.CharField(max_length=10, choices=Fuente.choices)

    # Polígono del municipio: el IDEAM publica un raster que se agrega por municipio.
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


class IncendioReportado(models.Model):
    """Incendio forestal reportado a la UNGRD (consolidado de emergencias).
    Son reportes administrativos, no un censo: sirven para validar el modelo
    de recurrencia contra lo observado en terreno."""

    # Dataset de datos.gov.co + id de fila de Socrata: hacen idempotente la carga.
    dataset = models.CharField(max_length=20)
    codigo = models.CharField(max_length=40)
    fecha = models.DateField()
    evento = models.CharField(max_length=60)
    # Nulo si el código DIVIPOLA del reporte no existe en el catálogo.
    municipio = models.ForeignKey(
        Municipio, null=True, blank=True, on_delete=models.SET_NULL, related_name="incendios_reportados"
    )
    # Texto tal como lo reportó la UNGRD, para trazar los que quedaron sin municipio.
    municipio_reportado = models.CharField(max_length=150, blank=True, default="")
    hectareas = models.FloatField(null=True, blank=True)

    class Meta:
        verbose_name = "incendio reportado"
        verbose_name_plural = "incendios reportados"
        ordering = ["-fecha"]
        constraints = [models.UniqueConstraint(fields=["dataset", "codigo"], name="incendio_reportado_unico")]
        indexes = [models.Index(fields=["fecha"]), models.Index(fields=["municipio", "fecha"])]

    def __str__(self):
        return f"{self.evento} {self.fecha} ({self.municipio_reportado})"
