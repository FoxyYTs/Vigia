import 'package:flutter/material.dart';

import '../core/theme/vigia_theme.dart';

/// Isotipo de Vigía (llama dentro de un recuadro) + nombre, como en el
/// diseño de Stitch. Decorativo para lectores de pantalla: el texto "Vigía"
/// ya lo nombra.
class VigiaMarca extends StatelessWidget {
  const VigiaMarca({super.key, this.subtitulo, this.claro = true, this.tamano = 40});

  final String? subtitulo;
  final bool claro;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final colorTexto = claro ? Colors.white : VigiaColors.texto;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: tamano,
            height: tamano,
            decoration: BoxDecoration(
              color: claro ? Colors.white.withValues(alpha: 0.12) : VigiaColors.bosque,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(
              Icons.local_fire_department,
              color: const Color(0xFFFFB59B),
              size: tamano * 0.6,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Vigía',
              style: TextStyle(
                color: colorTexto,
                fontSize: tamano * 0.55,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            if (subtitulo != null)
              Text(
                subtitulo!,
                style: TextStyle(
                  color: claro ? const Color(0xFFD4EBDC) : VigiaColors.textoSecundario,
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
