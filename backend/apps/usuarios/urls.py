from django.urls import path
from rest_framework.routers import DefaultRouter
from apps.usuarios.views import CerrarSesionView, MunicipioViewSet, RefrescoView, RegistroView, TokenView, YoView

router = DefaultRouter()
router.register("municipios", MunicipioViewSet, basename="municipio")

urlpatterns = [
    path("auth/registro/", RegistroView.as_view(), name="registro"),
    path("auth/token/", TokenView.as_view(), name="token"),
    path("auth/token/refresh/", RefrescoView.as_view(), name="token-refresh"),
    path("auth/logout/", CerrarSesionView.as_view(), name="logout"),
    path("auth/yo/", YoView.as_view(), name="yo"),
] + router.urls
