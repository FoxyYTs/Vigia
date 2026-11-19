from rest_framework.routers import SimpleRouter

from apps.satelital.views import FocoIncendioViewSet

router = SimpleRouter()
router.register("focos", FocoIncendioViewSet, basename="foco")

urlpatterns = router.urls
