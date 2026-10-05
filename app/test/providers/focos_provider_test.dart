import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/models/foco.dart';
import 'package:vigia_app/providers/focos_provider.dart';

/// Backend falso con [total] focos, paginado de 500 en 500 como DRF.
VigiaApi _apiCon(int total, {List<Uri>? pedidas}) => VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) async {
        pedidas?.add(r.url);
        if (r.url.path.endsWith('/ultimo/')) {
          return http.Response(jsonEncode({'fecha_hora': '2026-09-24T00:20:00Z'}), 200);
        }
        final fuente = r.url.queryParameters['fuente'];
        if (fuente != null && r.url.queryParameters['page_size'] == '1') {
          // Conteo por fuente: 2/3 FIRMS y 1/3 INPE.
          final n = fuente == 'NASA_FIRMS' ? total * 2 ~/ 3 : total - total * 2 ~/ 3;
          return http.Response(jsonEncode({'count': n, 'next': null, 'results': []}), 200);
        }
        final pagina = int.parse(r.url.queryParameters['page']!);
        final inicio = (pagina - 1) * 500;
        final n = (total - inicio).clamp(0, 500);
        return http.Response(
          jsonEncode({
            'count': total,
            'next': inicio + n < total ? 'siguiente' : null,
            'results': [
              for (var i = 0; i < n; i++)
                {
                  'id': inicio + i,
                  'fuente': 'NASA_FIRMS',
                  'latitud': 4.0,
                  'longitud': -72.0,
                  'fecha_hora': '2026-09-23T10:00:00Z',
                },
            ],
          }),
          200,
        );
      }),
    );

void main() {
  test('arranca en la fecha del último foco cargado y trae todas las páginas', () async {
    final p = FocosProvider(api: _apiCon(1200));

    await p.inicializar();

    expect(p.corte, DateTime.utc(2026, 9, 24, 0, 20));
    expect(p.total, 1200);
    expect(p.focos, hasLength(1200));
    expect(p.truncado, isFalse);
    expect(p.error, isNull);
  });

  test('con más focos que el máximo dibuja solo los primeros y lo indica', () async {
    final pedidas = <Uri>[];
    final p = FocosProvider(api: _apiCon(3000, pedidas: pedidas), maximoFocos: 1000);

    await p.inicializar();

    expect(p.focos, hasLength(1000));
    expect(p.total, 3000);
    expect(p.truncado, isTrue);
    expect(pedidas.where((u) => u.queryParameters['page_size'] == '500'), hasLength(2));
  });

  test('con truncado, el desglose por fuente suma el total y no solo lo dibujado', () async {
    final p = FocosProvider(api: _apiCon(3000), maximoFocos: 1000);

    await p.inicializar();

    expect(p.contarPorFuente(FuenteSatelital.nasaFirms), 2000);
    expect(p.contarPorFuente(FuenteSatelital.inpeQueimadas), 1000);
    expect(
      p.contarPorFuente(FuenteSatelital.nasaFirms) + p.contarPorFuente(FuenteSatelital.inpeQueimadas),
      p.total,
    );
  });

  test('sin truncado, el desglose se cuenta en el cliente sin peticiones extra', () async {
    final pedidas = <Uri>[];
    final p = FocosProvider(api: _apiCon(1200, pedidas: pedidas));

    await p.inicializar();

    expect(p.contarPorFuente(FuenteSatelital.nasaFirms), 1200);
    expect(p.contarPorFuente(FuenteSatelital.inpeQueimadas), 0);
    expect(pedidas.where((u) => u.queryParameters['page_size'] == '1'), isEmpty);
  });

  test('cambiar la ventana recalcula el rango pedido a la API', () async {
    final pedidas = <Uri>[];
    final p = FocosProvider(api: _apiCon(10, pedidas: pedidas));
    await p.inicializar();

    p.cambiarVentana(Ventana.d7);
    await Future<void>.delayed(Duration.zero);
    while (p.cargando) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    final ultima = pedidas.last.queryParameters;
    expect(ultima['desde'], '2026-09-17T00:20:00.000Z');
    expect(ultima['hasta'], '2026-09-24T00:20:00.000Z');
  });
}
