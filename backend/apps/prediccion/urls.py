from rest_framework.routers import SimpleRouter

from apps.prediccion.views import ZonaRecurrenteViewSet

router = SimpleRouter()
router.register("zonas-recurrentes", ZonaRecurrenteViewSet, basename="zona-recurrente")

urlpatterns = router.urls
