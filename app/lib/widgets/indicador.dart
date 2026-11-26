import 'package:flutter/material.dart';

import 'formato.dart';

/// Cifra grande con su etiqueta e ícono (Estadísticas, Históricos).
class Indicador extends StatelessWidget {
  const Indicador(this.etiqueta, this.valor, this.icono, {super.key});

  final String etiqueta;
  final int valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(icono, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Formato.entero(valor), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    Text(etiqueta, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
