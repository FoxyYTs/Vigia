from django.urls import path
from rest_framework.routers import DefaultRouter

from apps.notificaciones.views import NotificacionViewSet, estado_bot, probar_canal

router = DefaultRouter()
router.register("notificaciones", NotificacionViewSet, basename="notificacion")

urlpatterns = [
    path("bot-telegram/", estado_bot, name="estado-bot"),
    path("bot-telegram/probar/", probar_canal, name="probar-canal"),
    *router.urls,
]
