import 'package:flutter/material.dart';

/// Periodos de Estadísticas e Informes: 7, 30, 90 días o un año, hasta hoy.
class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({super.key, required this.dias, required this.onCambio});

  static const opciones = [7, 30, 90, 365];

  final int dias;

  /// null mientras no se puede cambiar (p. ej. generando un informe).
  final ValueChanged<int>? onCambio;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in opciones)
            ChoiceChip(
              label: Text(d == 365 ? '1 año' : '$d días'),
              selected: dias == d,
              onSelected: onCambio == null ? null : (_) => onCambio!(d),
            ),
        ],
      );
}
