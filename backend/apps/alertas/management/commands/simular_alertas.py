"""
Simulación de escenarios de alerta con datos de prueba (V3, issue #19):
dispara en vivo las 4 condiciones de `MotorAlertas` en zonas fijas de
Antioquia, con un foco y ciudadanos marcados como demo.

    python manage.py simular_alertas            # crea el escenario
    python manage.py simular_alertas --limpiar  # borra todo lo de demo

Las alertas se despachan por Celery, así que el worker debe estar arriba
para que lleguen los mensajes de Telegram.
"""

import time

from django.contrib.auth.hashers import UNUSABLE_PASSWORD_PREFIX
from django.contrib.gis.geos import Point
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.alertas.models import Alerta, AlertaReporte
from apps.alertas.motor import MotorAlertas
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Usuario

PREFIJO = "demo_sim_"
SATELITE_DEMO = "DEMO"
# Zonas separadas >10 km entre sí para que cada escenario dispare su propia condición.
SANTA_FE = Point(-75.8270, 6.5570, srid=4326)
SAN_JERONIMO = Point(-75.7270, 6.4440, srid=4326)
SOPETRAN = Point(-75.7430, 6.5010, srid=4326)
CERCA = 0.01  # ~1 km en grados


class Command(BaseCommand):
    help = "Simula las 4 condiciones de alerta con datos de demo (o las borra con --limpiar)."

    def add_arguments(self, parser):
        parser.add_argument("--limpiar", action="store_true", help="Borra los datos de demo.")
        parser.add_argument("--pausa", type=float, default=3, help="Segundos entre escenarios.")

    def handle(self, *args, limpiar=False, pausa=3, **opciones):
        if limpiar:
            return self.limpiar()
        motor = MotorAlertas()
        ciudadanos = [self.usuario(f"ciudadano{i}", Usuario.Rol.CIUDADANO) for i in range(1, 4)]
        admin = self.usuario("admin", Usuario.Rol.ADMINISTRADOR)

        self.paso("1. Detección satelital (foco en Santa Fe de Antioquia)")
        foco = FocoIncendio.objects.create(
            fuente=FocoIncendio.Fuente.NASA_FIRMS,
            ubicacion=SANTA_FE,
            fecha_hora=timezone.now(),
            confianza="h",
            satelite=SATELITE_DEMO,
        )
        self.resultado(motor.evaluar_foco_nuevo(foco))
        time.sleep(pausa)

        self.paso("2. Coincidencia geográfica (reporte a ~1 km del foco)")
        r = self.reporte(ciudadanos[0], Point(SANTA_FE.x + CERCA, SANTA_FE.y, srid=4326))
        self.resultado(motor.evaluar_reporte_nuevo(r))
        time.sleep(pausa)

        self.paso("3. Acumulación (3 ciudadanos distintos en San Jerónimo)")
        for i, c in enumerate(ciudadanos):
            r = self.reporte(c, Point(SAN_JERONIMO.x, SAN_JERONIMO.y + i * CERCA, srid=4326))
            alerta = motor.evaluar_reporte_nuevo(r)
            self.stdout.write(f"   reporte de {c.username}: {alerta or 'sin alerta todavía'}")
        time.sleep(pausa)

        self.paso("4. Validación manual (un administrador valida un reporte en Sopetrán)")
        r = self.reporte(ciudadanos[0], SOPETRAN)
        r.validar(admin)
        self.resultado(motor.evaluar_validacion_manual(r))
        self.stdout.write(self.style.SUCCESS("Listo. Para borrar: simular_alertas --limpiar"))

    def usuario(self, nombre, rol):
        u, creado = Usuario.objects.get_or_create(username=PREFIJO + nombre, defaults={"rol": rol})
        if creado:
            u.set_unusable_password()
            u.save(update_fields=["password"])
        return u

    def reporte(self, ciudadano, incendio):
        return ReporteCiudadano.objects.create(
            ciudadano=ciudadano,
            foto="reportes/demo.jpg",
            ubicacion_usuario=incendio,
            ubicacion_incendio=incendio,
            descripcion="Reporte de simulación",
        )

    def paso(self, texto):
        self.stdout.write(self.style.MIGRATE_HEADING(texto))

    def resultado(self, alerta):
        self.stdout.write(f"   → {alerta or 'sin alerta'}")

    @transaction.atomic
    def limpiar(self):
        # El prefijo solo no basta: cualquiera puede registrarse como "demo_sim_x".
        # Los de demo se crean sin contraseña usable, y eso no se logra registrándose.
        demo = Usuario.objects.filter(
            username__startswith=PREFIJO, password__startswith=UNUSABLE_PASSWORD_PREFIX
        )
        reportes = ReporteCiudadano.objects.filter(ciudadano__in=demo)
        focos = FocoIncendio.objects.filter(satelite=SATELITE_DEMO)
        # Una alerta con algún reporte real no se borra; solo se le quitan los de demo.
        reales = ReporteCiudadano.objects.exclude(ciudadano__in=demo)
        alertas, _ = (
            Alerta.objects.filter(Q(reportes__in=reportes) | Q(foco__in=focos))
            .exclude(reportes__in=reales)
            .distinct()
            .delete()
        )
        AlertaReporte.objects.filter(reporte__in=reportes).delete()
        n_reportes, _ = reportes.delete()
        n_focos, _ = focos.delete()
        n_usuarios, _ = demo.delete()
        self.stdout.write(
            self.style.SUCCESS(
                f"Borrado: {alertas} objetos de alertas, {n_reportes} de reportes, "
                f"{n_focos} de focos, {n_usuarios} de usuarios."
            )
        )
