from django.urls import path
from rest_framework.routers import DefaultRouter

from apps.historico.views import IncendioReportadoViewSet, capa_historica, capa_historica_disponible

router = DefaultRouter()
router.register("incendios-reportados", IncendioReportadoViewSet, basename="incendio-reportado")

urlpatterns = [
    path("historico/capa/", capa_historica, name="capa-historica"),
    path("historico/capa/disponible/", capa_historica_disponible, name="capa-historica-disponible"),
    *router.urls,
]
