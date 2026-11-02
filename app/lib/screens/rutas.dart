/// Rutas de la app. Siguen el mapa de navegación (vault: Vigia-Mapa-Navegacion):
///
/// ```
/// Vigía ─┬─ Mapa Interactivo            (/       público)
///        └─ Iniciar Sesión              (/login)
///             └─ Gestionar X (panel)     (/panel  requiere sesión)
/// ```
class Rutas {
  const Rutas._();

  static const mapa = '/';
  static const login = '/login';
  static const panel = '/panel';
}
