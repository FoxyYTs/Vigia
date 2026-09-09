from .base import *  # noqa: F401,F403

DEBUG = True

# Flutter Web se sirve por el mismo Nginx (mismo origen) — ver
# Vigia-UML-Despliegue, vault de Obsidian. No se necesita CORS para eso;
# la app móvil tampoco está sujeta a CORS (solo aplica a navegadores).
