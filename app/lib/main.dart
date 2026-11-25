import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'core/theme/vigia_theme.dart';
import 'data/api/vigia_api.dart';
import 'data/storage/almacen_tokens.dart';
import 'providers/auth_provider.dart';
import 'providers/focos_provider.dart';
import 'providers/historico_provider.dart';
import 'providers/prediccion_provider.dart';
import 'providers/preferencias_provider.dart';
import 'screens/bot_telegram_screen.dart';
import 'screens/estadisticas_screen.dart';
import 'screens/historicos_screen.dart';
import 'screens/informes_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mapa_screen.dart';
import 'screens/panel_screen.dart';
import 'screens/permisos_screen.dart';
import 'screens/reportes_screen.dart';
import 'screens/registro_screen.dart';
import 'screens/rutas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = VigiaApi(baseUrl: AppConfig.apiBaseUrl);
  final auth = AuthProvider(api: api, almacen: AlmacenTokensSeguro())..restaurar();
  // Se espera para que el primer frame salga ya con el tema elegido.
  final preferencias = PreferenciasProvider(almacen: const FlutterSecureStorage());
  await preferencias.cargar();
  runApp(VigiaApp(api: api, auth: auth, preferencias: preferencias));
}

class VigiaApp extends StatelessWidget {
  const VigiaApp({super.key, required this.api, required this.auth, required this.preferencias});

  final VigiaApi api;
  final AuthProvider auth;
  final PreferenciasProvider preferencias;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<VigiaApi>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<PreferenciasProvider>.value(value: preferencias),
        ChangeNotifierProvider(create: (_) => FocosProvider(api: api)),
        ChangeNotifierProvider(create: (_) => PrediccionProvider(api: api)),
        ChangeNotifierProvider(create: (_) => HistoricoProvider(api: api)),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          title: 'Vigía',
          debugShowCheckedModeBanner: false,
          theme: construirTemaVigia(),
          darkTheme: construirTemaVigia(brillo: Brightness.dark),
          themeMode: context.select<PreferenciasProvider, ThemeMode>((p) => p.tema),
          locale: const Locale('es', 'CO'),
          supportedLocales: const [Locale('es', 'CO'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          initialRoute: Rutas.mapa,
          onGenerateRoute: (ajustes) => MaterialPageRoute(
            settings: ajustes,
            builder: (_) => switch (ajustes.name) {
              Rutas.login => const LoginScreen(),
              Rutas.registro => const RegistroScreen(),
              Rutas.panel => const RequiereSesion(child: PanelScreen()),
              Rutas.reportes => const RequiereSesion(child: ReportesScreen()),
              Rutas.estadisticas => const RequiereSesion(gestion: true, child: EstadisticasScreen()),
              Rutas.historicos => const RequiereSesion(gestion: true, child: HistoricosScreen()),
              Rutas.botTelegram => const RequiereSesion(gestion: true, child: BotTelegramScreen()),
              Rutas.permisos => const RequiereSesion(gestion: true, child: PermisosScreen()),
              Rutas.informes => const RequiereSesion(gestion: true, child: InformesScreen()),
              _ => const MapaScreen(),
            },
          ),
        ),
      ),
    );
  }
}

/// El panel cuelga de "Iniciar Sesión": sin sesión se muestra el login.
class RequiereSesion extends StatelessWidget {
  const RequiereSesion({super.key, this.gestion = false, required this.child});

  /// Solo para administradores y staff (el ciudadano ni ve el bloque).
  final bool gestion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.estado) {
      EstadoSesion.verificando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      EstadoSesion.anonima => const LoginScreen(),
      EstadoSesion.autenticada when gestion && !auth.rol.gestiona => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No tienes permiso para ver esta página.')),
      ),
      EstadoSesion.autenticada => child,
    };
  }
}
