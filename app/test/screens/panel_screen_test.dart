import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/panel_screen.dart';
import 'package:vigia_app/widgets/proximo_incremento.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), 200, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('el panel muestra los bloques del mapa de navegación, incluido Gestionar Permisos', (t) async {
    t.view.physicalSize = const Size(1280, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final api = VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) async => r.url.path.endsWith('auth/token/')
          ? _json({'access': jwtFalso(username: 'ana'), 'refresh': 'r'})
          : _json({'id': 1, 'username': 'ana', 'email': 'ana@vigia.test', 'rol': 'ciudadano'})),
    );
    final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
    await auth.iniciarSesion('ana', 'clave');

    await t.pumpWidget(MultiProvider(
      providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
      child: const MaterialApp(home: PanelScreen()),
    ));
    await t.pumpAndSettle();

    for (final bloque in const [
      'Gestionar Usuario',
      'Gestionar Permisos',
      'Gestionar Reportar Focos de Incendios',
      'Gestionar Estadísticas',
      'Gestionar Históricos',
      'Gestionar Informes',
      'Gestionar Bot de Telegram',
    ]) {
      expect(find.text(bloque), findsOneWidget, reason: bloque);
    }
    // Perfil real en Gestionar Usuario; el resto rotulado como pendiente.
    expect(find.text('ana@vigia.test'), findsOneWidget);
    expect(find.byType(ProximoIncremento), findsNWidgets(6));
  });
}
