import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/models/foco.dart';
import '../providers/focos_provider.dart';
import 'formato.dart';

/// Filtros, contador y leyenda del Mapa Interactivo. Se usa como panel
/// lateral en escritorio y dentro de una hoja inferior en móvil.
class PanelFiltros extends StatelessWidget {
  const PanelFiltros({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FocosProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Titulo('Rango temporal'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in Ventana.values)
              ChoiceChip(
                label: Text(v.etiqueta),
                selected: p.ventana == v,
                onSelected: (_) => p.cambiarVentana(v),
                selectedColor: VigiaColors.bosqueClaro,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _SelectorCorte(p),
        const SizedBox(height: 20),
        const _Titulo('Fuente satelital'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todas'),
              selected: p.fuente == null,
              onSelected: (_) => p.cambiarFuente(null),
              selectedColor: VigiaColors.bosqueClaro,
            ),
            for (final f in FuenteSatelital.values)
              ChoiceChip(
                avatar: _Punto(colorFuente(f)),
                label: Text(f.etiqueta),
                selected: p.fuente == f,
                onSelected: (_) => p.cambiarFuente(f),
                selectedColor: VigiaColors.bosqueClaro,
              ),
          ],
        ),
        const SizedBox(height: 20),
        const ContadorFocos(),
        const SizedBox(height: 20),
        const Leyenda(),
      ],
    );
  }
}

Color colorFuente(FuenteSatelital? f) =>
    f == FuenteSatelital.inpeQueimadas ? VigiaColors.inpe : VigiaColors.firms;

class _SelectorCorte extends StatelessWidget {
  const _SelectorCorte(this.p);

  final FocosProvider p;

  @override
  Widget build(BuildContext context) {
    final corte = p.corte;
    final desde = p.desde;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: corte == null
              ? null
              : () async {
                  final dia = await showDatePicker(
                    context: context,
                    initialDate: corte.toLocal(),
                    firstDate: DateTime(2018, 4, 1),
                    lastDate: DateTime.now(),
                    helpText: 'Fecha de corte',
                    cancelText: 'Cancelar',
                    confirmText: 'Aplicar',
                  );
                  if (dia != null) p.cambiarCorte(dia);
                },
          icon: const Icon(Icons.event_outlined),
          label: Text(corte == null ? 'Fecha de corte' : 'Hasta ${Formato.fecha(corte)}'),
        ),
        if (corte != null && desde != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Del ${Formato.fechaHora(desde)} al ${Formato.fechaHora(corte)}',
              style: const TextStyle(fontSize: 12, color: VigiaColors.textoSecundario),
            ),
          ),
      ],
    );
  }
}

class ContadorFocos extends StatelessWidget {
  const ContadorFocos({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FocosProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FOCOS DETECTADOS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              if (p.cargando && p.focos.isEmpty)
                const LinearProgressIndicator()
              else
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: Formato.entero(p.total),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: '  focos', style: TextStyle(color: VigiaColors.textoSecundario)),
                  ]),
                ),
              const Text('en el rango seleccionado', style: TextStyle(color: VigiaColors.textoSecundario)),
              if (p.truncado) ...[
                const SizedBox(height: 8),
                Text(
                  'Se dibujan los ${Formato.entero(p.focos.length)} más recientes. '
                  'Acota el rango para ver el resto.',
                  style: const TextStyle(fontSize: 12, color: VigiaColors.fuego, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              for (final f in FuenteSatelital.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      _Punto(colorFuente(f)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f.etiqueta)),
                      Text(Formato.entero(p.contarPorFuente(f)),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              if (p.ultimoDisponible != null) ...[
                const Divider(height: 20),
                Text(
                  'Último foco cargado: ${Formato.fechaHora(p.ultimoDisponible!)}',
                  style: const TextStyle(fontSize: 12, color: VigiaColors.textoSecundario),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Leyenda extends StatelessWidget {
  const Leyenda({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titulo('Leyenda'),
        for (final (f, detalle) in const [
          (FuenteSatelital.nasaFirms, 'VIIRS (NOAA-20, NOAA-21, Suomi NPP)'),
          (FuenteSatelital.inpeQueimadas, 'Programa Queimadas, INPE (Brasil)'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _Punto(colorFuente(f), tamano: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(detalle, style: const TextStyle(fontSize: 12, color: VigiaColors.textoSecundario)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Text(
          'El tamaño del círculo crece con la potencia radiativa del fuego (FRP).',
          style: TextStyle(fontSize: 12, color: VigiaColors.textoSecundario),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child: Text(texto.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
      );
}

class _Punto extends StatelessWidget {
  const _Punto(this.color, {this.tamano = 10});

  final Color color;
  final double tamano;

  @override
  Widget build(BuildContext context) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
}
