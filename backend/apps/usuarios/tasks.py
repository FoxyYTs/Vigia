from celery import shared_task
from django.core.mail import send_mail

from apps.usuarios.recuperacion import VIGENCIA_SEGUNDOS


@shared_task
def enviar_codigo_recuperacion(email: str, username: str, codigo: str) -> None:
    """En segundo plano: así la respuesta tarda lo mismo exista o no la cuenta."""
    send_mail(
        subject=f"Vigía: tu código para restablecer la contraseña es {codigo}",
        message=(
            f"Hola, {username}:\n\n"
            f"Tu código para restablecer la contraseña de Vigía es:\n\n    {codigo}\n\n"
            f"Vence en {VIGENCIA_SEGUNDOS // 60} minutos. Escríbelo en la app junto con tu nueva contraseña.\n\n"
            "Si no lo pediste, ignora este correo: tu contraseña sigue igual.\n"
        ),
        from_email=None,
        recipient_list=[email],
    )
