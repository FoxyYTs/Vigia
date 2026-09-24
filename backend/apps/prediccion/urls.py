from rest_framework.routers import DefaultRouter

from apps.prediccion.views import ZonaRecurrenteViewSet

router = DefaultRouter()
router.register("zonas-recurrentes", ZonaRecurrenteViewSet, basename="zona-recurrente")

urlpatterns = router.urls
