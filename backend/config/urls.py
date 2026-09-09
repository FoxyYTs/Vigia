"""
URLs raíz. Cada app expone su propio `urls.py` bajo /api/ — se van
agregando aquí a medida que existan (objetivo específico 3).
"""

from django.contrib import admin
from django.urls import path

urlpatterns = [
    path("admin/", admin.site.urls),
]
