"""
Municipio, EntidadPublica, Usuario — ver Vigia-Modelo-Datos § Catálogo/Identidad
(vault de Obsidian).
"""

from django.contrib.auth.models import AbstractUser
from django.contrib.gis.db import models


class Municipio(models.Model):
    nombre = models.CharField(max_length=100)
    departamento = models.CharField(max_length=100)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["nombre", "departamento"], name="municipio_unico_por_departamento"
            ),
        ]

    def __str__(self):
        return f"{self.nombre}, {self.departamento}"


class EntidadPublica(models.Model):
    nombre = models.CharField(max_length=150, unique=True)
    # Jurisdicción por lista de municipios — decisión registrada en
    # Vigia-Modelo-Datos § Decisiones (no polígono real todavía).
    municipios = models.ManyToManyField(Municipio, related_name="entidades", blank=True)

    def __str__(self):
        return self.nombre


class Usuario(AbstractUser):
    class Rol(models.TextChoices):
        CIUDADANO = "ciudadano", "Ciudadano"
        ADMINISTRADOR = "administrador", "Administrador"
        STAFF = "staff", "Staff"

    # default=STAFF (no CIUDADANO): sin esto, un superusuario creado con
    # createsuperuser queda con rol='' — encontrado probando de verdad
    # (createsuperuser no falla, pero es_administrador()/es_staff() daban
    # False los dos). Quien crea un superusuario es por definición del
    # equipo de desarrollo; los flujos de registro de ciudadano/admin
    # deben fijar el rol explícitamente de todas formas.
    rol = models.CharField(max_length=20, choices=Rol.choices, default=Rol.STAFF)

    # Solo aplica a rol=ciudadano.
    municipio_residencia = models.ForeignKey(
        Municipio, null=True, blank=True, on_delete=models.SET_NULL, related_name="residentes"
    )

    # Solo aplica a rol=administrador; staff no lleva entidad.
    entidad = models.ForeignKey(
        EntidadPublica, null=True, blank=True, on_delete=models.SET_NULL, related_name="administradores"
    )

    def es_ciudadano(self) -> bool:
        return self.rol == self.Rol.CIUDADANO

    def es_administrador(self) -> bool:
        return self.rol == self.Rol.ADMINISTRADOR

    def es_staff(self) -> bool:
        """Rol de dominio 'staff' (ver Vigia-UML-Clases § Servicios) —
        distinto de `is_staff` (campo heredado de AbstractUser, acceso al
        admin de Django), aunque en la práctica todo usuario con
        rol=staff también debería tener is_staff=True."""
        return self.rol == self.Rol.STAFF
