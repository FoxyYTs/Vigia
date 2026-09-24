from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from apps.usuarios.models import Municipio, Usuario


class MunicipioSerializer(serializers.ModelSerializer):
    class Meta:
        model = Municipio
        fields = ["id", "nombre", "departamento"]


class UsuarioSerializer(serializers.ModelSerializer):
    class Meta:
        model = Usuario
        fields = ["id", "username", "email", "rol", "municipio_residencia", "entidad"]
        read_only_fields = fields


class RegistroSerializer(serializers.ModelSerializer):
    """Registro público: SIEMPRE crea un ciudadano. Administradores y staff
    los crea el equipo desde el Django Admin, nunca por autoservicio."""

    password = serializers.CharField(write_only=True, style={"input_type": "password"})
    email = serializers.EmailField(required=True)

    class Meta:
        model = Usuario
        fields = ["id", "username", "email", "password", "municipio_residencia"]

    def validate_email(self, valor):
        if Usuario.objects.filter(email__iexact=valor).exists():
            raise serializers.ValidationError("Ya existe una cuenta con este correo.")
        return valor

    def validate(self, datos):
        # Se valida con el usuario candidato para que la política de
        # contraseñas pueda rechazar las parecidas al nombre/correo.
        validate_password(datos["password"], Usuario(username=datos["username"], email=datos["email"]))
        return datos

    def create(self, datos):
        return Usuario.objects.create_user(rol=Usuario.Rol.CIUDADANO, **datos)


class TokenVigiaSerializer(TokenObtainPairSerializer):
    """Agrega el rol al JWT para que la app decida qué pantallas mostrar sin
    una llamada extra (la autorización real siempre se valida en el backend)."""

    @classmethod
    def get_token(cls, usuario):
        token = super().get_token(usuario)
        token["rol"] = usuario.rol
        token["username"] = usuario.username
        return token
