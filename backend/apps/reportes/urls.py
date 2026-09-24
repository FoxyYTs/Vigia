from rest_framework.routers import DefaultRouter

from apps.reportes.views import ReporteCiudadanoViewSet

router = DefaultRouter()
router.register("reportes", ReporteCiudadanoViewSet, basename="reporte")

urlpatterns = router.urls
