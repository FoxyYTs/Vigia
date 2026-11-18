/// Rutas de la app. Siguen el mapa de navegación (vault: Vigia-Mapa-Navegacion):
///
/// ```
/// Vigía ─┬─ Mapa Interactivo            (/       público)
///        └─ Iniciar Sesión              (/login)
///             └─ Gestionar X (panel)     (/panel  requiere sesión)
///                  ├─ Reportar Focos     (/reportes)
///                  ├─ Estadísticas       (/estadisticas)
///                  ├─ Históricos         (/historicos)
///                  ├─ Informes           (/informes)
///                  └─ Bot de Telegram    (/bot-telegram)
/// ```
class Rutas {
  const Rutas._();

  static const mapa = '/';
  static const login = '/login';
  static const panel = '/panel';
  static const reportes = '/reportes';
  static const estadisticas = '/estadisticas';
  static const informes = '/informes';
  static const historicos = '/historicos';
  static const botTelegram = '/bot-telegram';
}
