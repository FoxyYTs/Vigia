"""
CorridaModeloML, ZonaRecurrente — ver Vigia-Modelo-Datos § Satelital/predicción
(vault de Obsidian). `ModeloRecurrencia` (el servicio que las crea) se
agrega después.

Las zonas se guardan por corrida y no se sobrescriben en cada
re-entrenamiento: permite comparar cómo evolucionan las zonas de riesgo.
"""

from django.contrib.gis.db import models
from django.utils import timezone

from apps.usuarios.models import Municipio


class CorridaModeloML(models.Model):
    fecha_ejecucion = models.DateTimeField(default=timezone.now)
    version_modelo = models.CharField(max_length=50)
    notas = models.TextField(blank=True, default="")

    class Meta:
        verbose_name = "corrida del modelo"
        verbose_name_plural = "corridas del modelo"
        ordering = ["-fecha_ejecucion"]

    def __str__(self):
        return f"{self.version_modelo} @ {self.fecha_ejecucion:%Y-%m-%d %H:%M}"


class ZonaRecurrente(models.Model):
    corrida = models.ForeignKey(CorridaModeloML, on_delete=models.CASCADE, related_name="zonas")
    area = models.MultiPolygonField(srid=4326)
    puntaje_recurrencia = models.FloatField()
    cantidad_incendios_historicos = models.PositiveIntegerField()
    municipio = models.ForeignKey(
        Municipio, null=True, blank=True, on_delete=models.SET_NULL, related_name="zonas_recurrentes"
    )

    class Meta:
        verbose_name = "zona recurrente"
        verbose_name_plural = "zonas recurrentes"
        ordering = ["-puntaje_recurrencia"]

    def __str__(self):
        return f"Zona (puntaje {self.puntaje_recurrencia:.2f}) — corrida {self.corrida_id}"
