from django.urls import path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from apps.usuarios.views import MunicipioViewSet, RegistroView, TokenView, YoView

router = DefaultRouter()
router.register("municipios", MunicipioViewSet, basename="municipio")

urlpatterns = [
    path("auth/registro/", RegistroView.as_view(), name="registro"),
    path("auth/token/", TokenView.as_view(), name="token"),
    path("auth/token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    path("auth/yo/", YoView.as_view(), name="yo"),
] + router.urls
