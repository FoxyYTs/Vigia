from django.urls import path

from apps.administracion.views import estadisticas_view, informe_view

urlpatterns = [
    path("estadisticas/", estadisticas_view, name="estadisticas"),
    path("informes/", informe_view, name="informes"),
]
