"""
Notificacion — ver Vigia-Modelo-Datos § Reportes y alertas (vault de Obsidian).
Los servicios `Notificador*` y `DespachadorNotificaciones` se agregan después.

Exclusivamente saliente (push / Telegram hacia el usuario). Telegram nunca es
canal de entrada de reportes: un reporte sin cuenta autenticada rompería la
trazabilidad.
"""

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.alertas.models import Alerta


class Notificacion(models.Model):
    class Canal(models.TextChoices):
        PUSH_APP = "push_app", "Push (app)"
        TELEGRAM_PUBLICO = "telegram_publico", "Telegram público"
        TELEGRAM_PRIVADO = "telegram_privado", "Telegram privado"
        TELEGRAM_INTERNO = "telegram_interno", "Telegram interno"

    class Estado(models.TextChoices):
        ENVIADO = "enviado", "Enviado"
        LEIDO = "leido", "Leído"
        FALLIDO = "fallido", "Fallido"

    alerta = models.ForeignKey(Alerta, on_delete=models.CASCADE, related_name="notificaciones")
    # null = canal público de Telegram, que no tiene una cuenta destinataria.
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name="notificaciones",
    )
    canal = models.CharField(max_length=20, choices=Canal.choices)
    estado = models.CharField(max_length=10, choices=Estado.choices, default=Estado.ENVIADO)
    fecha_envio = models.DateTimeField(default=timezone.now)
    fecha_lectura = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "notificación"
        verbose_name_plural = "notificaciones"
        ordering = ["-fecha_envio"]

    def __str__(self):
        return f"Notificación #{self.pk} ({self.canal}, {self.estado})"
