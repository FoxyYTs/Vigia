from rest_framework.routers import SimpleRouter

from apps.reportes.views import ReporteCiudadanoViewSet

router = SimpleRouter()
router.register("reportes", ReporteCiudadanoViewSet, basename="reporte")

urlpatterns = router.urls
