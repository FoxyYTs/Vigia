import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Skeleton de carga (vault: Normas/Diseno-UI-UX/Skeleton-Screens): dibuja el
/// [child] real, hecho con datos de ejemplo, como bloques grises. Así el
/// layout no salta cuando llegan los datos.
///
/// - No aparece antes de [espera]: con respuestas rápidas parpadearía.
/// - Sin animación si el sistema pide reducir movimiento (WCAG 2.3.3).
/// - El lector de pantalla oye «Cargando» en vez de los datos de ejemplo.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, required this.child, this.espera = const Duration(milliseconds: 300)});

  final Widget child;
  final Duration espera;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto> {
  late final Timer _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.espera, () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final gris = cs.surfaceContainerHighest;
    final efecto = MediaQuery.disableAnimationsOf(context)
        ? SolidColorEffect(color: gris)
        : ShimmerEffect(
            baseColor: gris,
            highlightColor: cs.surfaceContainerLow,
            duration: const Duration(milliseconds: 1500),
          );
    return Semantics(
      label: 'Cargando',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AbsorbPointer(
          child: Visibility.maintain(
            visible: _visible,
            child: Skeletonizer(
              effect: efecto,
              // Barras e íconos de acento no se vuelven bloques: en gris, para
              // que los datos de ejemplo no parezcan un gráfico real.
              child: Theme(
                data: tema.copyWith(
                  colorScheme: cs.copyWith(
                    primary: gris,
                    secondary: gris,
                    primaryContainer: gris,
                    onPrimaryContainer: cs.surfaceContainerLow,
                    tertiaryContainer: cs.surfaceContainerLow,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
