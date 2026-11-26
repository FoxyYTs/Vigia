import 'package:flutter/material.dart';

import '../data/api/vigia_api.dart';

/// Carga de una pantalla: indicador mientras espera, error con «Reintentar»
/// y el [contenido] cuando llegan los datos. El mensaje de una [ApiException]
/// se muestra tal cual; cualquier otro error, con [mensajeError].
class EstadoCarga<T> extends StatelessWidget {
  const EstadoCarga({
    super.key,
    required this.futuro,
    required this.mensajeError,
    required this.onReintentar,
    required this.contenido,
  });

  final Future<T> futuro;
  final String mensajeError;
  final VoidCallback onReintentar;
  final Widget Function(T datos) contenido;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: futuro,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasError: true, :final error) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error is ApiException ? error.mensaje : mensajeError,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onReintentar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) => contenido(data as T),
          _ => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        },
      );
}
