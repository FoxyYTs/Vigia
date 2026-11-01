import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/providers/prediccion_provider.dart';
import 'package:vigia_app/widgets/panel_filtros.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

Map<String, Object> _zona(int id, double puntaje) => {
      'id': id,
      'corrida': 1,
      'mes_objetivo': '2026-11-01',
      'puntaje_recurrencia': puntaje,
      'cantidad_incendios_historicos': 4,
      'municipio': 'Rionegro, Antioquia',
      'area': {
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [[-75.4, 6.1], [-75.4, 6.2], [-75.3, 6.2], [-75.3, 6.1], [-75.4, 6.1]],
          ],
        ],
      },
    };

/// Backend falso: 3 meses; el mes pedido tiene [porMes] zonas, paginadas de 500.
VigiaApi _api({Map<String, int> porMes = const {'2026-11': 2, '2026-12': 1200}, List<Uri>? pedidas, Future<void>? lento}) =>
    VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) async {
        pedidas?.add(r.url);
        if (r.url.path.endsWith('/meses/')) {
          return _json({
            'corrida': 1,
            'fecha_ejecucion': '2026-11-02T09:00:00Z',
            'meses': ['2026-11', '2026-12', '2027-01'],
            'metricas': {},
          });
        }
        final mes = r.url.queryParameters['mes']!;
        if (mes == '2026-11' && lento != null) await lento;
        final total = porMes[mes] ?? 0;
        final inicio = (int.parse(r.url.queryParameters['page']!) - 1) * 500;
        final n = (total - inicio).clamp(0, 500);
        return _json({
          'count': total,
          'next': inicio + n < total ? 'siguiente' : null,
          'results': [for (var i = 0; i < n; i++) _zona(inicio + i, 0.6)],
        });
      }),
    );

void main() {
  test('oculta no pide nada; al mostrarla carga los meses y el primero', () async {
    final pedidas = <Uri>[];
    final p = PrediccionProvider(api: _api(pedidas: pedidas));
    expect(p.zonas, isEmpty);
    expect(pedidas, isEmpty);

    await p.mostrar(true);

    expect(p.meses, ['2026-11', '2026-12', '2027-01']);
    expect(p.mes, '2026-11');
    expect(p.zonas, hasLength(2));
    expect(p.zonas.first.contorno.first.latitude, 6.1);
    expect(p.zonas.first.municipio, 'Rionegro, Antioquia');
    expect(pedidas.last.queryParameters['min_puntaje'], '0.3');
  });

  test('cambiar de mes trae todas las páginas', () async {
    final pedidas = <Uri>[];
    final p = PrediccionProvider(api: _api(pedidas: pedidas));
    await p.mostrar(true);

    await p.cambiarMes('2026-12');

    expect(p.zonas, hasLength(1200));
    expect(pedidas.where((u) => u.queryParameters['mes'] == '2026-12'), hasLength(3));
  });

  test('al ocultarla el mapa deja de dibujar zonas, pero no se vuelven a pedir', () async {
    final pedidas = <Uri>[];
    final p = PrediccionProvider(api: _api(pedidas: pedidas));
    await p.mostrar(true);
    await p.mostrar(false);
    expect(p.zonas, isEmpty);

    final antes = pedidas.length;
    await p.mostrar(true);
    expect(p.zonas, hasLength(2));
    expect(pedidas, hasLength(antes));
  });

  test('una respuesta vieja no pisa la del mes elegido después', () async {
    final lenta = Completer<void>();
    final p = PrediccionProvider(api: _api(lento: lenta.future));
    final primera = p.mostrar(true); // pide 2026-11, que tarda
    while (p.mes == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await p.cambiarMes('2026-12');
    lenta.complete();
    await primera;

    expect(p.mes, '2026-12');
    expect(p.zonas, hasLength(1200));
  });

  test('sin corridas avisa que todavía no hay predicciones', () async {
    final api = VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((_) async => _json({'corrida': null, 'meses': []})),
    );
    final p = PrediccionProvider(api: api);
    await p.mostrar(true);
    expect(p.error, contains('todavía no tiene predicciones'));
    expect(p.cargando, isFalse);
  });

  test('colorPuntaje y nombreMes', () {
    expect(colorPuntaje(0.31), tramosPuntaje[0].$3);
    expect(colorPuntaje(0.9), tramosPuntaje[3].$3);
    expect(nombreMes('2027-01'), 'enero 2027');
  });

  testWidgets('el panel muestra el interruptor, los meses y la leyenda', (t) async {
    final p = PrediccionProvider(api: _api());
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider.value(value: p, child: const SingleChildScrollView(child: PanelPrediccion())),
      ),
    ));
    expect(find.text('noviembre 2026'), findsNothing);

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    expect(find.text('noviembre 2026'), findsOneWidget);
    expect(find.text('enero 2027'), findsOneWidget);
    expect(find.text('Probabilidad Más de 85 %'), findsOneWidget);
    expect(find.textContaining('No es un pronóstico del clima'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Zonas de recurrencia')), findsWidgets);

    await t.tap(find.text('diciembre 2026'));
    await t.pumpAndSettle();
    expect(p.mes, '2026-12');
  });
}
