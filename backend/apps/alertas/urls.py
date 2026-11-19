from rest_framework.routers import SimpleRouter

from apps.alertas.views import AlertaViewSet

router = SimpleRouter()
router.register("alertas", AlertaViewSet, basename="alerta")

urlpatterns = router.urls
