from rest_framework.routers import DefaultRouter

from apps.satelital.views import FocoIncendioViewSet

router = DefaultRouter()
router.register("focos", FocoIncendioViewSet, basename="foco")

urlpatterns = router.urls
