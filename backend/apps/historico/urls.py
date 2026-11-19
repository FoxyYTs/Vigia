from django.urls import path
from rest_framework.routers import SimpleRouter

from apps.historico.views import (
    IncendioReportadoViewSet,
    capa_historica,
    capa_historica_disponible,
    resumen_historicos,
    sincronizar_ungrd_view,
)

router = SimpleRouter()
router.register("incendios-reportados", IncendioReportadoViewSet, basename="incendio-reportado")

urlpatterns = [
    path("historico/capa/", capa_historica, name="capa-historica"),
    path("historico/capa/disponible/", capa_historica_disponible, name="capa-historica-disponible"),
    path("historico/resumen/", resumen_historicos, name="resumen-historicos"),
    path("historico/ungrd/sincronizar/", sincronizar_ungrd_view, name="sincronizar-ungrd"),
    *router.urls,
]
