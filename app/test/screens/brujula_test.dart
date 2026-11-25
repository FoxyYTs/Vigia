import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vigia_app/screens/mapa_screen.dart';

void main() {
  testWidgets('la brújula aparece con el mapa girado y lo devuelve al norte', (t) async {
    final mapa = MapController();
    await t.pumpWidget(MaterialApp(
      home: Stack(children: [
        FlutterMap(
          mapController: mapa,
          options: const MapOptions(initialCenter: LatLng(6.15, -75.37), initialZoom: 6),
          children: const [],
        ),
        Align(alignment: Alignment.topRight, child: BotonBrujula(mapa: mapa)),
      ]),
    ));
    final brujula = find.byTooltip('Orientar al norte');
    expect(brujula, findsNothing);

    mapa.rotate(45);
    await t.pump();
    expect(brujula, findsOneWidget);

    await t.tap(brujula);
    await t.pump();
    expect(mapa.camera.rotation, 0);
    expect(brujula, findsNothing);
  });
}
