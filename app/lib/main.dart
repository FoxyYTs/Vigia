import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'core/theme/vigia_theme.dart';
import 'data/api/vigia_api.dart';
import 'data/storage/almacen_tokens.dart';
import 'providers/auth_provider.dart';
import 'providers/focos_provider.dart';
import 'screens/login_screen.dart';
import 'screens/mapa_screen.dart';
import 'screens/panel_screen.dart';
import 'screens/rutas.dart';

void main() {
  final api = VigiaApi(baseUrl: AppConfig.apiBaseUrl);
  final auth = AuthProvider(api: api, almacen: AlmacenTokensSeguro())..restaurar();
  runApp(VigiaApp(api: api, auth: auth));
}

class VigiaApp extends StatelessWidget {
  const VigiaApp({super.key, required this.api, required this.auth});

  final VigiaApi api;
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<VigiaApi>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => FocosProvider(api: api)),
      ],
      child: MaterialApp(
        title: 'Vigía',
        debugShowCheckedModeBanner: false,
        theme: construirTemaVigia(),
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: Rutas.mapa,
        onGenerateRoute: (ajustes) => MaterialPageRoute(
          settings: ajustes,
          builder: (_) => switch (ajustes.name) {
            Rutas.login => const LoginScreen(),
            Rutas.panel => const _RequiereSesion(child: PanelScreen()),
            _ => const MapaScreen(),
          },
        ),
      ),
    );
  }
}

/// El panel cuelga de "Iniciar Sesión": sin sesión se muestra el login.
class _RequiereSesion extends StatelessWidget {
  const _RequiereSesion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.estado) {
      EstadoSesion.verificando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      EstadoSesion.anonima => const LoginScreen(),
      EstadoSesion.autenticada => child,
    };
  }
}
