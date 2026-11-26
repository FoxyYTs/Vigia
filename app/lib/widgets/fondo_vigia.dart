import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fondo de las pantallas con contenido: curvas de nivel tenues en dos
/// esquinas, como un mapa topográfico. Le quita lo plano a la superficie sin
/// competir con las tarjetas (que son opacas y van encima).
class FondoVigia extends StatelessWidget {
  const FondoVigia({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: oscuro ? 0.10 : 0.07);
    return CustomPaint(
      painter: _CurvasDeNivel(color),
      isComplex: true,
      // El contenido (listas que se desplazan) repinta en su propia capa: el
      // fondo se dibuja una vez y no en cada cuadro del scroll.
      child: RepaintBoundary(child: child),
    );
  }
}

class _CurvasDeNivel extends CustomPainter {
  _CurvasDeNivel(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final lado = math.max(size.width, size.height);
    // Dos "cerros": arriba a la derecha y abajo a la izquierda.
    for (final (centro, fase) in [
      (Offset(size.width * 0.95, size.height * 0.05), 0.0),
      (Offset(size.width * 0.05, size.height * 1.0), 1.7),
    ]) {
      for (var k = 1; k <= 14; k++) {
        final radio = lado * 0.035 * k;
        final camino = Path();
        for (var i = 0; i <= 120; i++) {
          final t = i / 120 * 2 * math.pi;
          // Ondulación distinta por curva para que no sean círculos concéntricos.
          final r = radio * (1 + 0.09 * math.sin(3 * t + k * 0.45 + fase) + 0.05 * math.sin(5 * t - k * 0.3));
          final p = centro + Offset(math.cos(t) * r, math.sin(t) * r * 0.8);
          i == 0 ? camino.moveTo(p.dx, p.dy) : camino.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(camino..close(), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_CurvasDeNivel viejo) => viejo.color != color;
}
