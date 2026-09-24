"""
Permisos por rol — ver Vigia-UML-Casos-Uso. El rol "anónimo" no existe en
la base de datos: es la ausencia de sesión (endpoints con AllowAny).
Se pueden combinar con `|`, ej. `EsCiudadano | EsAdministrador`.
"""

from rest_framework.permissions import BasePermission

from apps.usuarios.models import Usuario


class _PorRol(BasePermission):
    roles: tuple = ()

    def has_permission(self, request, view):
        usuario = request.user
        return bool(usuario and usuario.is_authenticated and usuario.rol in self.roles)


class EsCiudadano(_PorRol):
    roles = (Usuario.Rol.CIUDADANO,)


class EsAdministrador(_PorRol):
    roles = (Usuario.Rol.ADMINISTRADOR,)


class EsStaff(_PorRol):
    roles = (Usuario.Rol.STAFF,)
