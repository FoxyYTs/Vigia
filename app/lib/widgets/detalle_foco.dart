import 'package:flutter/material.dart';

import '../core/theme/vigia_theme.dart';
import '../data/models/foco.dart';
import 'formato.dart';
import 'panel_filtros.dart' show colorFuente;

/// Detalle del foco tocado en el mapa.
class DetalleFoco extends StatelessWidget {
  const DetalleFoco({super.key, required this.foco, required this.onCerrar});

  final Foco foco;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final filas = <(String, String)>[
      ('Fuente', foco.fuente?.etiqueta ?? 'Desconocida'),
      if (foco.satelite.isNotEmpty) ('Satélite', foco.satelite),
      ('Fecha y hora', Formato.fechaHora(foco.fechaHora)),
      ('Latitud', Formato.coordenada(foco.posicion.latitude, latitud: true)),
      ('Longitud', Formato.coordenada(foco.posicion.longitude, latitud: false)),
      ('Confianza', foco.confianzaLegible),
      ('Potencia (FRP)',
          foco.brilloFrp == null ? 'No reportada' : '${foco.brilloFrp!.toStringAsFixed(1).replaceAll('.', ',')} MW'),
    ];

    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department, color: colorFuente(foco.fuente)),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Foco de calor #${foco.id}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  icon: const Icon(Icons.close),
                  onPressed: onCerrar,
                ),
              ],
            ),
            const Divider(height: 8),
            for (final (etiqueta, valor) in filas)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(etiqueta, style: const TextStyle(color: VigiaColors.textoSecundario)),
                    ),
                    Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
