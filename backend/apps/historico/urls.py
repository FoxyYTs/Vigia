from rest_framework.routers import DefaultRouter

from apps.historico.views import IncendioReportadoViewSet

router = DefaultRouter()
router.register("incendios-reportados", IncendioReportadoViewSet, basename="incendio-reportado")

urlpatterns = router.urls
