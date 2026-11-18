"""
Estadísticas de incidentes por región y periodo (UC7, bloque "Gestionar
Estadísticas"). Se calculan al vuelo, sin persistencia, igual que los informes.
"""

from datetime import date, datetime, time, timedelta

from django.db.models import Count, Exists, OuterRef, Subquery
from django.db.models.functions import TruncDate
from django.utils import timezone

from apps.alertas.models import Alerta
from apps.reportes.models import ReporteCiudadano
from apps.reportes.views import _como_geometry
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

# Un año de focos tarda ~2,5 s en agruparse por departamento (879 mil focos).
DIAS_MAXIMOS = 366


def jurisdiccion(usuario):
    """Municipios con polígono de la entidad del administrador, o None si ve
    todo el país (staff, o administrador sin entidad o sin polígonos), con la
    misma regla que los reportes ciudadanos."""
    if not (usuario.es_administrador() and usuario.entidad_id):
        return None
    municipios = Municipio.objects.filter(entidades=usuario.entidad_id, geom__isnull=False)
    return municipios if municipios.exists() else None


def _en(municipios, campo):
    return Exists(municipios.filter(geom__contains=OuterRef(campo)))


def _contar(qs, campo):
    return [
        {"clave": f[campo], "cantidad": f["cantidad"]}
        for f in qs.values(campo).annotate(cantidad=Count("id")).order_by("-cantidad", campo)
    ]


def consultas(desde: date, hasta: date, municipios=None):
    """Focos, alertas y reportes de [desde, hasta] (inclusivo, hora de
    Colombia), limitados a [municipios] si no es None. Los usan también los
    informes, para que cuenten exactamente lo mismo."""
    zona = timezone.get_current_timezone()
    inicio = datetime.combine(desde, time.min, zona)
    fin = datetime.combine(hasta + timedelta(days=1), time.min, zona)

    focos = FocoIncendio.objects.filter(fecha_hora__gte=inicio, fecha_hora__lt=fin).annotate(
        punto=_como_geometry("ubicacion")
    )
    alertas = Alerta.objects.filter(fecha_creacion__gte=inicio, fecha_creacion__lt=fin)
    reportes = ReporteCiudadano.objects.filter(fecha_creacion__gte=inicio, fecha_creacion__lt=fin).annotate(
        punto=_como_geometry("ubicacion_incendio")
    )
    if municipios is not None:
        focos = focos.filter(_en(municipios, "punto"))
        alertas = alertas.filter(municipio__in=municipios)
        reportes = reportes.filter(_en(municipios, "punto"))
    return focos, alertas, reportes


def municipio_del_punto():
    """Subconsulta del municipio que contiene `punto` (anotado por `consultas`)."""
    return Municipio.objects.filter(geom__contains=OuterRef("punto"))


def calcular(desde: date, hasta: date, municipios=None) -> dict:
    """Resumen del periodo, con los mismos filtros de `consultas`."""
    zona = timezone.get_current_timezone()
    focos, alertas, reportes = consultas(desde, hasta, municipios)

    departamento = municipio_del_punto().values("departamento")[:1]
    por_departamento = _contar(focos.annotate(departamento=Subquery(departamento)), "departamento")
    por_dia = (
        focos.annotate(dia=TruncDate("fecha_hora", tzinfo=zona))
        .values("dia")
        .annotate(cantidad=Count("id"))
        .order_by("dia")
    )
    conteo_dia = {f["dia"]: f["cantidad"] for f in por_dia}

    return {
        "desde": desde,
        "hasta": hasta,
        "nacional": municipios is None,
        "focos": {
            "total": focos.count(),
            "por_fuente": _contar(focos, "fuente"),
            # clave None: foco fuera de los municipios con polígono (mar, frontera).
            "por_departamento": por_departamento,
            # Todos los días del periodo, con 0 donde no hubo: sin eso, el
            # gráfico juntaba días separados por huecos.
            "por_dia": [
                {"dia": desde + timedelta(days=i), "cantidad": conteo_dia.get(desde + timedelta(days=i), 0)}
                for i in range((hasta - desde).days + 1)
            ],
        },
        "alertas": {
            "total": alertas.count(),
            "por_tipo": _contar(alertas, "tipo_disparador"),
            "por_departamento": _contar(alertas, "municipio__departamento"),
        },
        "reportes": {
            "total": reportes.count(),
            "por_estado": _contar(reportes, "estado"),
        },
    }
