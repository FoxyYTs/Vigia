## Qué cambia y por qué

<!-- Issue relacionado: #… -->

## Cómo se probó

- [ ] `pytest` y `ruff check` en verde (backend)
- [ ] `flutter analyze` y `flutter test` en verde (app)
- [ ] Probado en el stack real (`docker compose up`) si toca backend, Nginx o la app

## Revisión

- [ ] Sin secretos en el código ni en los logs
- [ ] Datos personales: ¿cambia qué se guarda, quién lo ve o cuánto se conserva? (Ley 1581)
- [ ] Accesibilidad: etiquetas semánticas y estados de carga/error/vacío (WCAG 2.2)
- [ ] `CHANGELOG.md` actualizado en "Sin publicar"
