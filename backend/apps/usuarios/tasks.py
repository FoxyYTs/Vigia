from celery import shared_task
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string

from apps.usuarios.recuperacion import VIGENCIA_SEGUNDOS

SITIO = "https://vigia.foxyyts.qzz.io/"


@shared_task
def enviar_codigo_recuperacion(email: str, username: str, codigo: str) -> None:
    """En segundo plano: así la respuesta tarda lo mismo exista o no la cuenta.
    El código va en el cuerpo y no en el asunto, que se ve en notificaciones
    y en la bandeja sin abrir el correo."""
    contexto = {"username": username, "codigo": codigo, "minutos": VIGENCIA_SEGUNDOS // 60, "sitio": SITIO}
    correo = EmailMultiAlternatives(
        subject="Vigía: código para restablecer tu contraseña",
        body=render_to_string("usuarios/correo_recuperacion.txt", contexto),
        to=[email],
    )
    correo.attach_alternative(render_to_string("usuarios/correo_recuperacion.html", contexto), "text/html")
    correo.send()
