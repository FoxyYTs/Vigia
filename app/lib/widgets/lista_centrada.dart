import 'dart:math';

import 'package:flutter/material.dart';

import 'fondo_vigia.dart';

/// Lista desplazable con el contenido centrado y un ancho máximo, para que en
/// pantallas anchas no se estire de borde a borde. En el celular deja 16 px.
class ListaCentrada extends StatelessWidget {
  const ListaCentrada({super.key, required this.children, this.maximo = amplio});

  /// Pantallas con rejillas de tarjetas (estadísticas, históricos, bot).
  static const double amplio = 1500;

  /// Listas y formularios (informes, permisos).
  static const double lectura = 1000;

  final List<Widget> children;
  final double maximo;

  @override
  Widget build(BuildContext context) => FondoVigia(
        child: ListView(
          padding: EdgeInsets.symmetric(
            vertical: 16,
            horizontal: max(16, (MediaQuery.sizeOf(context).width - maximo) / 2),
          ),
          children: children,
        ),
      );
}
