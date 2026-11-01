import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/models/historico.dart';
import 'package:vigia_app/providers/historico_provider.dart';
import 'package:vigia_app/providers/prediccion_provider.dart';
import 'package:vigia_app/widgets/panel_filtros.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

Map<String, Object> _municipio(String codigo, String nombre) => {
      'type': 'Feature',
      'properties': {'codigo_dane': codigo, 'nombre': nombre, 'departamento': 'Antioquia'},
      'geometry': {
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [[-75.4, 6.1], [-75.4, 6.2], [-75.3, 6.2], [-75.4, 6.1]],
          ],
        ],
      },
    };

/// Backend falso: 3 municipios; incendios 2023–2024 y deforestación 2024–2025.
VigiaApi _api({List<Uri>? pedidas, Future<void>? lento}) => VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) async {
        pedidas?.add(r.url);
        if (r.url.path.endsWith('municipios/geometria/')) {
          return _json({
            'type': 'FeatureCollection',
            'features': [_municipio('05615', 'Rionegro'), _municipio('05440', 'Marinilla'), _municipio('05001', 'Medellín')],
          });
        }
        if (r.url.path.endsWith('capa/disponible/')) {
          return _json({'incendios_ungrd': [2023, 2024], 'deforestacion_ideam': [2024, 2025]});
        }
        final q = r.url.queryParameters;
        if (q['anio'] == '2023' && lento != null) await lento;
        return _json(switch ((q['indicador'], q['anio'])) {
          ('incendios_ungrd', '2024') => [
              {'codigo_dane': '05615', 'valor': 9},
              {'codigo_dane': '05440', 'valor': 1},
            ],
          ('incendios_ungrd', '2023') => [{'codigo_dane': '05001', 'valor': 4}],
          ('deforestacion_ideam', _) => [{'codigo_dane': '05440', 'valor': 120.5}],
          _ => <Object>[],
        });
      }),
    );

void main() {
  test('oculta no pide nada; al mostrarla carga geometría, años y el último año', () async {
    final pedidas = <Uri>[];
    final h = HistoricoProvider(api: _api(pedidas: pedidas));
    expect(h.coloreados, isEmpty);
    expect(pedidas, isEmpty);

    await h.mostrar(true);

    expect(h.anios, [2023, 2024]);
    expect(h.anio, 2024);
    expect({for (final (m, _) in h.coloreados) m.nombre}, {'Rionegro', 'Marinilla'});
    expect(h.coloreados.first.$1.anillos.first.first.latitude, 6.1);
  });

  test('la geometría se pide una sola vez aunque cambien indicador y año', () async {
    final pedidas = <Uri>[];
    final h = HistoricoProvider(api: _api(pedidas: pedidas));
    await h.mostrar(true);
    await h.cambiarAnio(2023);
    await h.cambiarIndicador(IndicadorHistorico.deforestacionIdeam);
    await h.mostrar(false);
    await h.mostrar(true);

    expect(pedidas.where((u) => u.path.endsWith('geometria/')), hasLength(1));
    // 2023 no existe en deforestación: se pasa al último año disponible.
    expect(h.anio, 2025);
    expect(h.valorDe('05440'), 120.5);
  });

  test('una respuesta vieja no pisa la del año elegido después', () async {
    final lenta = Completer<void>();
    final h = HistoricoProvider(api: _api(lento: lenta.future));
    await h.mostrar(true);
    final vieja = h.cambiarAnio(2023);
    await h.cambiarAnio(2024);
    lenta.complete();
    await vieja;
    expect(h.anio, 2024);
    expect(h.valorDe('05615'), 9);
  });

  test('cuantiles: cortes sin repetidos y clase de cada valor', () {
    expect(cortesPorCuantiles([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 5), [2, 4, 6, 8]);
    // Con muchos valores iguales quedan menos clases, ninguna vacía.
    expect(cortesPorCuantiles([1, 1, 1, 1, 1, 1, 1, 1, 2, 9], 5), [1]);
    expect(cortesPorCuantiles([], 5), isEmpty);
    final h = HistoricoProvider(api: _api());
    expect(h.claseDe(3), 0); // sin cortes todo es la clase 0
  });

  test('etiquetas de la leyenda', () {
    expect(etiquetasClases([2, 3, 6], IndicadorHistorico.incendiosUngrd),
        ['Hasta 2 incendios', '3 incendios', '4 – 6 incendios', 'Más de 6 incendios']);
    expect(etiquetasClases([10.4, 99.6], IndicadorHistorico.deforestacionIdeam),
        ['Hasta 10 ha', '10 – 100 ha', 'Más de 100 ha']);
    expect(etiquetasClases([], IndicadorHistorico.deforestacionIdeam), ['Con datos']);
  });

  testWidgets('activar Histórico apaga Predicción y al revés', (t) async {
    final h = HistoricoProvider(api: _api());
    final p = PrediccionProvider(
      api: VigiaApi(
        baseUrl: Uri.parse('https://vigia.test/api/'),
        cliente: MockClient((_) async => _json({'corrida': null, 'meses': []})),
      ),
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [ChangeNotifierProvider.value(value: h), ChangeNotifierProvider.value(value: p)],
          child: const SingleChildScrollView(child: Column(children: [PanelPrediccion(), PanelHistorico()])),
        ),
      ),
    ));

    await t.tap(find.text('Zonas de recurrencia'));
    await t.pumpAndSettle();
    expect(p.visible, isTrue);

    await t.tap(find.text('Histórico por municipio'));
    await t.pumpAndSettle();
    expect((h.visible, p.visible), (true, false));
    expect(find.text('Incendios reportados (UNGRD)'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.textContaining('Más de'), findsOneWidget);

    await t.tap(find.text('Deforestación (IDEAM)'));
    await t.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(find.textContaining('ha'), findsWidgets);

    await t.tap(find.text('Zonas de recurrencia'));
    await t.pumpAndSettle();
    expect((h.visible, p.visible), (false, true));
  });
}
