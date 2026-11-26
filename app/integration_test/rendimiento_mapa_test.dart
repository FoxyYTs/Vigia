// Medición de rendimiento del Mapa Interactivo en un celular real (#92).
//
//   flutter drive --profile -d <id> \
//     --dart-define=API_BASE_URL=https://vigia.foxyyts.qzz.io/api/ \
//     --driver=test_driver/rendimiento_driver.dart \
//     --target=integration_test/rendimiento_mapa_test.dart
//
// Deja build/mapa_31d_{mover,seleccionar}.timeline_summary.json (tiempos de build y raster por frame).
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/config/app_config.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/main.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/providers/focos_provider.dart';
import 'package:vigia_app/screens/mapa_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('mover el mapa con 31 días de focos', (tester) async {
    final api = VigiaApi(baseUrl: AppConfig.apiBaseUrl);
    await tester.pumpWidget(VigiaApp(api: api, auth: AuthProvider(api: api, almacen: AlmacenTokensSeguro())));

    final focos = tester.element(find.byType(MapaScreen)).read<FocosProvider>();
    Future<void> esperarCarga() async {
      final limite = DateTime.now().add(const Duration(seconds: 60));
      do {
        await tester.pump(const Duration(milliseconds: 200));
      } while ((focos.cargando || focos.corte == null) && DateTime.now().isBefore(limite));
      expect(focos.error, isNull);
    }

    await esperarCarga();
    focos.cambiarVentana(Ventana.d31);
    await esperarCarga();
    expect(focos.focos, isNotEmpty);

    final mapa = find.byType(FlutterMap);
    await binding.traceAction(reportKey: 'mapa_31d_mover', () async {
      for (final d in const [Offset(-250, 0), Offset(0, -250), Offset(250, 0), Offset(0, 250)]) {
        await tester.timedDrag(mapa, d, const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 300));
      }
      for (final boton in const ['Acercar', 'Acercar', 'Alejar', 'Alejar']) {
        await tester.tap(find.byTooltip(boton));
        await tester.pump(const Duration(milliseconds: 300));
      }
    });
    await binding.traceAction(reportKey: 'mapa_31d_seleccionar', () async {
      // Seleccionar redibuja el mapa: aquí se ve si reconstruye todas las capas.
      for (final f in focos.focos.take(10)) {
        focos.seleccionar(f);
        await tester.pump(const Duration(milliseconds: 150));
      }
      focos.seleccionar(null);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
