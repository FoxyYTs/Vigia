"""
MotorAlertas — ver Vigia-UML-Clases § Servicios y Vigia-UML-Secuencia
(vault de Obsidian). Decide cuándo un foco o un reporte se convierte en
`Alerta` y la manda a despachar.

Toda comparación contra reportes usa `ubicacion_incendio`, nunca
`ubicacion_usuario`: el ciudadano puede reportar desde lejos.
"""

from datetime import timedelta

from django.contrib.gis.measure import D
from django.db import transaction
from django.utils import timezone

from apps.alertas.models import Alerta, AlertaReporte
from apps.notificaciones.tasks import despachar_alerta
from apps.reportes.models import ReporteCiudadano
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

# Detección satelital: un foco no crea alerta si ya hay otra satelital
# cerca y reciente (decisión de José, 31-oct-2026) — evita una alerta por
# cada uno de los cientos de focos de una misma quema.
RADIO_AGRUPACION_SATELITAL_KM = 5
VENTANA_AGRUPACION_SATELITAL = timedelta(hours=24)
# Coincidencia geográfica: reporte ciudadano cerca de un foco reciente.
RADIO_COINCIDENCIA_KM = 10
VENTANA_FOCO_ACTIVO = timedelta(hours=24)
# Acumulación de reportes (DEF-I, 30-sep-2026): ≥3 ciudadanos distintos, 5 km, <1 h.
RADIO_ACUMULACION_KM = 5
VENTANA_ACUMULACION = timedelta(hours=1)
UMBRAL_CIUDADANOS = 3
# Una cuenta recién creada no cuenta para la acumulación: sin esto, tres
# cuentas falsas creadas en un minuto disparaban una alerta a las entidades.
ANTIGUEDAD_MINIMA_CUENTA = timedelta(hours=24)


class MotorAlertas:
    def evaluar_foco_nuevo(self, foco: FocoIncendio) -> Alerta | None:
        # VIIRS marca con 'l' (low) las detecciones dudosas; MODIS es numérico.
        if foco.confianza == "l":
            return None
        ya_hay = Alerta.objects.filter(
            tipo_disparador=Alerta.TipoDisparador.DETECCION_SATELITAL,
            ubicacion__distance_lte=(foco.ubicacion, D(km=RADIO_AGRUPACION_SATELITAL_KM)),
            fecha_creacion__gte=timezone.now() - VENTANA_AGRUPACION_SATELITAL,
        ).exists()
        if ya_hay:
            return None
        return self._crear(Alerta.TipoDisparador.DETECCION_SATELITAL, foco.ubicacion, foco=foco)

    def evaluar_reporte_nuevo(self, reporte: ReporteCiudadano) -> Alerta | None:
        ahora = timezone.now()
        punto = reporte.ubicacion_incendio

        foco = (
            FocoIncendio.objects.filter(
                ubicacion__distance_lte=(punto, D(km=RADIO_COINCIDENCIA_KM)),
                fecha_hora__gte=ahora - VENTANA_FOCO_ACTIVO,
            )
            .order_by("-fecha_hora")
            .first()
        )
        if foco:
            existente = Alerta.objects.filter(
                tipo_disparador=Alerta.TipoDisparador.COINCIDENCIA_GEOGRAFICA, foco=foco
            ).first()
            if existente:
                existente.reportes.add(reporte)
                return None
            # Va al canal público: se publica la ubicación del satélite, no el
            # pin del ciudadano, que aún no ha validado nadie.
            return self._crear(
                Alerta.TipoDisparador.COINCIDENCIA_GEOGRAFICA, foco.ubicacion, foco=foco, disparador=reporte
            )

        existente = Alerta.objects.filter(
            tipo_disparador=Alerta.TipoDisparador.ACUMULACION_REPORTES,
            ubicacion__distance_lte=(punto, D(km=RADIO_ACUMULACION_KM)),
            fecha_creacion__gte=ahora - VENTANA_ACUMULACION,
        ).first()
        if existente:
            existente.reportes.add(reporte)
            return None

        cercanos = ReporteCiudadano.objects.filter(
            ubicacion_incendio__distance_lte=(punto, D(km=RADIO_ACUMULACION_KM)),
            fecha_creacion__gte=ahora - VENTANA_ACUMULACION,
            ciudadano__date_joined__lte=ahora - ANTIGUEDAD_MINIMA_CUENTA,
        ).exclude(estado=ReporteCiudadano.Estado.RECHAZADO)
        if cercanos.values("ciudadano").distinct().count() < UMBRAL_CIUDADANOS:
            return None
        return self._crear(
            Alerta.TipoDisparador.ACUMULACION_REPORTES,
            punto,
            disparador=reporte,
            corroboran=cercanos.exclude(pk=reporte.pk),
        )

    def evaluar_validacion_manual(self, reporte: ReporteCiudadano) -> Alerta:
        return self._crear(
            Alerta.TipoDisparador.VALIDACION_MANUAL, reporte.ubicacion_incendio, disparador=reporte
        )

    @transaction.atomic
    def _crear(self, tipo, ubicacion, foco=None, disparador=None, corroboran=()) -> Alerta:
        municipio = Municipio.objects.filter(geom__contains=ubicacion).first()
        alerta = Alerta.objects.create(tipo_disparador=tipo, ubicacion=ubicacion, foco=foco, municipio=municipio)
        if disparador:
            AlertaReporte.objects.create(alerta=alerta, reporte=disparador, es_disparador=True)
        AlertaReporte.objects.bulk_create(
            [AlertaReporte(alerta=alerta, reporte=r) for r in corroboran]
        )
        transaction.on_commit(lambda: despachar_alerta.delay(alerta.pk))
        return alerta
