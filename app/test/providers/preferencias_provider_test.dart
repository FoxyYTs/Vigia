import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigia_app/providers/preferencias_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('por defecto sigue el tema del sistema y agrupa los focos', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final p = PreferenciasProvider(almacen: const FlutterSecureStorage());
    await p.cargar();
    expect(p.tema, ThemeMode.system);
    expect(p.agruparFocos, isTrue);
  });

  test('las preferencias se recuerdan al volver a abrir la app', () async {
    FlutterSecureStorage.setMockInitialValues({});
    PreferenciasProvider(almacen: const FlutterSecureStorage())
      ..cambiarTema(ThemeMode.dark)
      ..cambiarAgruparFocos(false);
    await Future<void>.delayed(Duration.zero);

    final reabierta = PreferenciasProvider(almacen: const FlutterSecureStorage());
    await reabierta.cargar();
    expect(reabierta.tema, ThemeMode.dark);
    expect(reabierta.agruparFocos, isFalse);
  });
}
