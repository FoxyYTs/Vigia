from datetime import timedelta

from django.http import HttpResponse
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from apps.administracion import estadisticas
from apps.administracion.exportador import CONJUNTOS, ExportadorDatos
from apps.usuarios.permissions import EsAdministrador, EsStaff


class PeriodoSerializer(serializers.Serializer):
    """`?desde=AAAA-MM-DD&hasta=AAAA-MM-DD`, ambos inclusivos. Por defecto, los
    últimos 30 días hasta hoy."""

    desde = serializers.DateField(required=False)
    hasta = serializers.DateField(required=False)

    def validate(self, datos):
        hasta = datos.get("hasta") or timezone.localdate()
        desde = datos.get("desde") or hasta - timedelta(days=29)
        if desde > hasta:
            raise serializers.ValidationError({"desde": "Debe ser anterior o igual a «hasta»."})
        if (hasta - desde).days >= estadisticas.DIAS_MAXIMOS:
            raise serializers.ValidationError({"desde": f"El periodo máximo es de {estadisticas.DIAS_MAXIMOS} días."})
        return {"desde": desde, "hasta": hasta}


@extend_schema(parameters=[PeriodoSerializer], responses=OpenApiTypes.OBJECT)
@api_view(["GET"])
@permission_classes([EsAdministrador | EsStaff])
def estadisticas_view(request):
    """Focos, alertas y reportes del periodo. El administrador de una entidad
    con polígonos solo ve su jurisdicción."""
    periodo = PeriodoSerializer(data=request.query_params)
    periodo.is_valid(raise_exception=True)
    return Response(estadisticas.calcular(**periodo.validated_data, municipios=estadisticas.jurisdiccion(request.user)))


DIAS_MAXIMOS_DETALLE = 92


class InformeSerializer(PeriodoSerializer):
    formato = serializers.ChoiceField(choices=["csv", "xlsx", "pdf"])
    # Solo para CSV: Excel lleva todos los conjuntos y el PDF es un resumen.
    conjunto = serializers.ChoiceField(choices=CONJUNTOS, default="focos")

    def validate(self, datos):
        datos = {**datos, **super().validate(datos)}
        # El detalle de un año en Excel tardaba ~18 s y ocupaba un worker de
        # gunicorn (timeout de 30 s); el PDF es un resumen y aguanta el año.
        if datos["formato"] != "pdf" and (datos["hasta"] - datos["desde"]).days >= DIAS_MAXIMOS_DETALLE:
            raise serializers.ValidationError(
                {"desde": f"El detalle en CSV o Excel admite hasta {DIAS_MAXIMOS_DETALLE} días; "
                          "usa el PDF para periodos más largos."}
            )
        return datos


TIPOS_MIME = {
    "csv": "text/csv; charset=utf-8",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "pdf": "application/pdf",
}


@extend_schema(
    parameters=[InformeSerializer],
    responses={(200, tipo.split(";")[0]): OpenApiTypes.BINARY for tipo in TIPOS_MIME.values()},
)
@api_view(["GET"])
@permission_classes([EsAdministrador | EsStaff])
def informe_view(request):
    """`?formato=csv|xlsx|pdf&desde=&hasta=` (y `conjunto=` para CSV): el
    informe como archivo descargable, con la jurisdicción de las estadísticas.
    (`formato` y no `format`: DRF reserva `format` para la negociación.)"""
    params = InformeSerializer(data=request.query_params)
    params.is_valid(raise_exception=True)
    d = params.validated_data
    exportador = ExportadorDatos(d["desde"], d["hasta"], estadisticas.jurisdiccion(request.user))
    formato = d["formato"]
    contenido = {
        "csv": lambda: exportador.exportar_csv(d["conjunto"]),
        "xlsx": exportador.exportar_excel,
        "pdf": exportador.exportar_pdf,
    }[formato]()
    nombre = f"vigia-{d['conjunto'] + '-' if formato == 'csv' else ''}{d['desde']}_{d['hasta']}.{formato}"
    respuesta = HttpResponse(contenido, content_type=TIPOS_MIME[formato])
    respuesta["Content-Disposition"] = f'attachment; filename="{nombre}"'
    return respuesta
