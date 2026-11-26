import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:vigia_app/widgets/esqueleto.dart';

Future<void> _montar(WidgetTester t, {bool sinAnimaciones = false}) => t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: sinAnimaciones),
        child: const Scaffold(body: Esqueleto(child: Text('dato de ejemplo'))),
      ),
    ));

// Skeletonizer() es un factory que devuelve una subclase: byType no la encuentra.
final _skeletonizer = find.byWidgetPredicate((w) => w is Skeletonizer);

void main() {
  testWidgets('aparece pasados 300 ms y el lector de pantalla oye «Cargando»', (t) async {
    final semantica = t.ensureSemantics();
    await _montar(t);
    expect(_skeletonizer, findsOneWidget);
    expect(t.widget<Visibility>(find.byType(Visibility)).visible, isFalse);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
    expect(find.bySemanticsLabel('dato de ejemplo'), findsNothing);
    semantica.dispose();
  });

  testWidgets('sin animación si el sistema pide reducir movimiento', (t) async {
    await _montar(t, sinAnimaciones: true);
    expect(t.widget<Skeletonizer>(_skeletonizer).effect, isA<SolidColorEffect>());
  });
}
