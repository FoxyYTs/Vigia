"""
URLs raíz. Cada app expone su propio `urls.py`; todo cuelga de /api/.
"""

from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerSplitView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("apps.usuarios.urls")),
    path("api/", include("apps.satelital.urls")),
    path("api/", include("apps.reportes.urls")),
    path("api/", include("apps.alertas.urls")),
    path("api/", include("apps.notificaciones.urls")),
    path("api/", include("apps.prediccion.urls")),
    path("api/", include("apps.historico.urls")),
    path("api/", include("apps.administracion.urls")),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    # Split: el script de arranque va en un archivo aparte, así lo admite la
    # CSP de Nginx (script-src 'self', sin inline).
    path("api/docs/", SpectacularSwaggerSplitView.as_view(url_name="schema"), name="docs"),
]

if settings.DEBUG:
    # En producción las fotos las sirve Nginx (volumen media_files).
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
