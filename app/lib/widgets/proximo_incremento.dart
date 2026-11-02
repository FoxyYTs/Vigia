import 'package:flutter/material.dart';

import '../core/theme/vigia_theme.dart';

/// Rótulo de las pantallas del mapa de navegación que todavía no están
/// implementadas: se muestran para que la navegación sea completa, pero no
/// simulan una función que no existe.
class ProximoIncremento extends StatelessWidget {
  const ProximoIncremento({super.key});

  static const texto = 'Próximo incremento';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: VigiaColors.superficie,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: VigiaColors.borde),
    ),
    child: const Text(texto, style: TextStyle(fontSize: 11, color: VigiaColors.textoSecundario)),
  );
}
