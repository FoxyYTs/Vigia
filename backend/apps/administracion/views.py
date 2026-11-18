from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from apps.administracion import estadisticas
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


@api_view(["GET"])
@permission_classes([EsAdministrador | EsStaff])
def estadisticas_view(request):
    """Focos, alertas y reportes del periodo. El administrador de una entidad
    con polígonos solo ve su jurisdicción."""
    periodo = PeriodoSerializer(data=request.query_params)
    periodo.is_valid(raise_exception=True)
    return Response(estadisticas.calcular(**periodo.validated_data, municipios=estadisticas.jurisdiccion(request.user)))
