import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Guarda el resumen de frames de cada `traceAction` en
/// `build/<clave>.timeline_summary.json`.
Future<void> main() => integrationDriver(
      responseDataCallback: (datos) async {
        for (final MapEntry(:key, :value) in (datos ?? const {}).entries) {
          final resumen = driver.TimelineSummary.summarize(driver.Timeline.fromJson(value as Map<String, dynamic>));
          await resumen.writeTimelineToFile(key, pretty: true, includeSummary: true);
        }
      },
    );
