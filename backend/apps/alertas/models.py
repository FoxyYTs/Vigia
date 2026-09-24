"""
Alerta, AlertaReporte — ver Vigia-Modelo-Datos § Reportes y alertas y
Vigia-UML-Secuencia (vault de Obsidian). `MotorAlertas` (el servicio que
las crea) se agrega después.
"""

from django.contrib.gis.db import models

from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio


class Alerta(models.Model):
    class TipoDisparador(models.TextChoices):
        DETECCION_SATELITAL = "deteccion_satelital", "Detección satelital"
        COINCIDENCIA_GEOGRAFICA = "coincidencia_geografica", "Coincidencia geográfica"
        ACUMULACION_REPORTES = "acumulacion_reportes", "Acumulación de reportes"
        VALIDACION_MANUAL = "validacion_manual", "Validación manual"

    # Guarda la condición exacta que la disparó, no solo que se disparó.
    tipo_disparador = models.CharField(max_length=30, choices=TipoDisparador.choices)
    foco = models.ForeignKey(
        FocoIncendio, null=True, blank=True, on_delete=models.SET_NULL, related_name="alertas"
    )
    reportes = models.ManyToManyField(
        ReporteCiudadano, through="AlertaReporte", related_name="alertas"
    )
    ubicacion = models.PointField(geography=True, srid=4326)
    municipio = models.ForeignKey(
        Municipio, null=True, blank=True, on_delete=models.SET_NULL, related_name="alertas"
    )
    fecha_creacion = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-fecha_creacion"]

    def __str__(self):
        return f"Alerta #{self.pk} ({self.tipo_disparador})"


class AlertaReporte(models.Model):
    """Tabla intermedia explícita: permite reconstruir el orden exacto en
    una investigación de reportes falsos."""

    alerta = models.ForeignKey(Alerta, on_delete=models.CASCADE)
    reporte = models.ForeignKey(ReporteCiudadano, on_delete=models.PROTECT)
    fecha_asociacion = models.DateTimeField(auto_now_add=True)
    # True en el reporte que cruzó el umbral; False en los de corroboración.
    es_disparador = models.BooleanField(default=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["alerta", "reporte"], name="alerta_reporte_unico"),
        ]

    def __str__(self):
        return f"Alerta {self.alerta_id} ↔ Reporte {self.reporte_id}"
