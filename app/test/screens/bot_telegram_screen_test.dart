import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/bot_telegram_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

const _estado = {
  'bot': 'VigiaAlertasBot',
  'token_configurado': true,
  'canales': [
    {
      'canal': 'telegram_publico',
      'nombre': 'Telegram público',
      'configurado': true,
      'alertas': ['coincidencia_geografica', 'validacion_manual'],
      'enviados_7d': 12,
      'fallidos_7d': 0,
      'ultimo_envio': '2026-11-18T20:00:00Z',
    },
    {
      'canal': 'telegram_privado',
      'nombre': 'Telegram privado',
      'configurado': true,
      'alertas': ['deteccion_satelital'],
      'enviados_7d': 40,
      'fallidos_7d': 3,
      'ultimo_envio': null,
    },
    {
      'canal': 'telegram_interno',
      'nombre': 'Telegram interno',
      'configurado': false,
      'alertas': ['acumulacion_reportes'],
      'enviados_7d': 0,
      'fallidos_7d': 0,
      'ultimo_envio': null,
    },
  ],
  'recientes': [
    {
      'fecha_envio': '2026-11-18T20:00:00Z',
      'canal': 'telegram_privado',
      'estado': 'fallido',
      'tipo_alerta': 'deteccion_satelital',
      'municipio': 'Puerto Carreño',
    },
  ],
};

Future<List<http.Request>> _montar(WidgetTester t, {required String rol, Map<String, Object?> estado = _estado}) async {
  t.view.physicalSize = const Size(1300, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <http.Request>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      if (r.url.path.endsWith('auth/token/')) return _json({'access': jwtFalso(rol: rol), 'refresh': 'r'});
      pedidas.add(r);
      return r.method == 'POST' ? _json({'detail': 'ok'}) : _json(estado);
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: const MaterialApp(home: BotTelegramScreen()),
  ));
  await t.pumpAndSettle();
  return pedidas;
}

void main() {
  testWidgets('muestra el bot, cada canal y los últimos envíos', (t) async {
    await _montar(t, rol: 'administrador');

    expect(find.text('El bot @VigiaAlertasBot está activo.'), findsOneWidget);
    expect(find.text('Sin configurar'), findsOneWidget);
    expect(find.text('Últimos 7 días: 40 enviados · 3 fallidos'), findsOneWidget);
    expect(find.text('• Acumulación de reportes'), findsOneWidget);
    expect(find.text('Detección satelital · Puerto Carreño'), findsOneWidget);
    expect(find.textContaining('Telegram privado · Fallido'), findsOneWidget);
    // Solo el staff manda pruebas.
    expect(find.text('Enviar prueba'), findsNothing);
  });

  testWidgets('sin token avisa que las alertas no salen', (t) async {
    await _montar(t, rol: 'administrador', estado: {..._estado, 'bot': null, 'token_configurado': false});
    expect(find.textContaining('no tiene token'), findsOneWidget);
  });

  testWidgets('el staff envía una prueba a un canal configurado', (t) async {
    final pedidas = await _montar(t, rol: 'staff');

    expect(find.text('Enviar prueba'), findsNWidgets(3));
    await t.tap(find.text('Enviar prueba').first);
    await t.pumpAndSettle();

    expect(pedidas.last.method, 'POST');
    expect(jsonDecode(pedidas.last.body), {'canal': 'telegram_publico'});
    expect(find.text('Mensaje de prueba enviado al canal Telegram público.'), findsOneWidget);
  });
}
