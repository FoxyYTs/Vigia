from rest_framework.routers import DefaultRouter

from apps.alertas.views import AlertaViewSet

router = DefaultRouter()
router.register("alertas", AlertaViewSet, basename="alerta")

urlpatterns = router.urls
