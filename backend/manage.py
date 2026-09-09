#!/usr/bin/env python
import os
import sys


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.local")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "No se pudo importar Django. ¿Está activado el entorno virtual "
            "e instaladas las dependencias de backend/requirements/?"
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
