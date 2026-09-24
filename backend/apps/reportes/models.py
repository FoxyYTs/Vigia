"""
ReporteCiudadano — ver Vigia-Modelo-Datos § Reportes y alertas (vault de Obsidian).

Dos ubicaciones separadas a propósito: `ubicacion_usuario` (GPS automático
al enviar) y `ubicacion_incendio` (pin manual en el mapa). El ciudadano puede
alejarse del peligro y aun así reportar dónde está el incendio; la distancia
entre ambas también sirve como señal para detectar reportes fraudulentos.
"""

from math import asin, cos, radians, sin, sqrt

from django.conf import settings
from django.contrib.gis.db import models
from django.utils import timezone

RADIO_TIERRA_KM = 6371.0088


class ReporteCiudadano(models.Model):
    class Estado(models.TextChoices):
        PENDIENTE = "pendiente", "Pendiente"
        VALIDADO = "validado", "Validado"
        RECHAZADO = "rechazado", "Rechazado"

    # PROTECT: un reporte es evidencia para investigar reportes falsos, no
    # se debe perder en silencio si se borra la cuenta.
    ciudadano = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="reportes",
        limit_choices_to={"rol": "ciudadano"},
    )
    foto = models.ImageField(upload_to="reportes/%Y/%m/")  # obligatoria
    ubicacion_usuario = models.PointField(geography=True, srid=4326)
    ubicacion_incendio = models.PointField(geography=True, srid=4326)
    descripcion = models.TextField(blank=True, default="")
    estado = models.CharField(max_length=10, choices=Estado.choices, default=Estado.PENDIENTE)
    validado_por = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="reportes_validados",
        limit_choices_to={"rol": "administrador"},
    )
    fecha_creacion = models.DateTimeField(auto_now_add=True)
    fecha_validacion = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "reporte ciudadano"
        verbose_name_plural = "reportes ciudadanos"
        ordering = ["-fecha_creacion"]
        indexes = [models.Index(fields=["estado", "fecha_creacion"])]

    def __str__(self):
        return f"Reporte #{self.pk} ({self.estado})"

    def _resolver(self, admin, estado):
        if not admin.es_administrador():
            raise PermissionError("Solo un administrador puede validar o rechazar reportes.")
        if self.estado != self.Estado.PENDIENTE:
            raise ValueError(f"El reporte ya está {self.estado}.")
        self.estado = estado
        self.validado_por = admin
        self.fecha_validacion = timezone.now()
        self.save(update_fields=["estado", "validado_por", "fecha_validacion"])

    def validar(self, admin) -> None:
        """Marca el reporte como validado. Crear la alerta que corresponda
        (validación manual) es responsabilidad de `MotorAlertas`, no de
        este modelo."""
        self._resolver(admin, self.Estado.VALIDADO)

    def rechazar(self, admin) -> None:
        self._resolver(admin, self.Estado.RECHAZADO)

    def distancia_reportada(self) -> float:
        """Distancia en km entre dónde estaba el ciudadano y dónde dice que
        está el incendio (fórmula de haversine, sin base de datos)."""
        a, b = self.ubicacion_usuario, self.ubicacion_incendio
        lat1, lon1, lat2, lon2 = map(radians, (a.y, a.x, b.y, b.x))
        h = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
        return 2 * RADIO_TIERRA_KM * asin(sqrt(h))
