import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../providers/auth_provider.dart';

/// "Gestionar Informes" (UC8): informes de apoyo a la decisión en PDF, Excel
/// y CSV, generados al vuelo por el backend con la jurisdicción del usuario.
class InformesScreen extends StatefulWidget {
  const InformesScreen({super.key, this.guardar});

  static const titulo = 'Gestionar Informes';

  /// Inyectable para las pruebas; por defecto, la hoja de compartir del
  /// sistema (en el navegador de escritorio, una descarga).
  final Future<void> Function(Uint8List bytes, String nombre, String tipoMime)? guardar;

  @override
  State<InformesScreen> createState() => _InformesScreenState();
}

class _InformesScreenState extends State<InformesScreen> {
  // El detalle (CSV, Excel) admite hasta 92 días; el PDF, un año.
  static const _periodos = [7, 30, 90, 365];
  static const _conjuntos = {'focos': 'Detecciones satelitales', 'alertas': 'Alertas', 'reportes': 'Reportes ciudadanos'};
  static const _tiposMime = {
    'pdf': 'application/pdf',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv': 'text/csv',
  };

  int _dias = 30;
  String _conjunto = 'focos';
  String? _generando;

  Future<void> _descargar(String formato) async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _generando = formato);
    try {
      final access = await context.read<AuthProvider>().accessToken();
      if (!mounted) return;
      final hoy = DateTime.now();
      final informe = await context.read<VigiaApi>().descargarInforme(
            access,
            formato: formato,
            conjunto: _conjunto,
            desde: hoy.subtract(Duration(days: _dias - 1)),
            hasta: hoy,
          );
      await (widget.guardar ?? _compartir)(informe.bytes, informe.nombre, _tiposMime[formato]!);
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (_) {
      // La hoja de compartir puede fallar (p. ej. en web, si el gesto del
      // usuario venció mientras el servidor generaba el archivo).
      mensajero.showSnackBar(const SnackBar(content: Text('No se pudo guardar el archivo. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _generando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final soloPdf = _dias > 92;
    return Scaffold(
      appBar: AppBar(title: const Text(InformesScreen.titulo)),
      body: ListView(
        // Centrado y con ancho máximo en pantallas anchas.
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: max(16, (MediaQuery.sizeOf(context).width - 800) / 2)),
        children: [
          const Text('Periodo (hasta hoy)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _periodos)
                ChoiceChip(
                  label: Text(d == 365 ? '1 año' : '$d días'),
                  selected: _dias == d,
                  onSelected: _generando != null ? null : (_) => setState(() => _dias = d),
                  selectedColor: VigiaColors.bosqueClaro,
                ),
            ],
          ),
          if (soloPdf)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Para un año solo está el PDF: el detalle en Excel o CSV admite hasta 92 días.',
                  style: TextStyle(color: VigiaColors.textoSecundario)),
            ),
          const SizedBox(height: 16),
          _Formato(
            icono: Icons.picture_as_pdf_outlined,
            titulo: 'Informe en PDF',
            corto: 'PDF',
            detalle: 'Resumen para la toma de decisiones: totales y tablas por departamento, fuente, '
                'disparador y estado.',
            generando: _generando == 'pdf',
            onDescargar: _generando == null ? () => _descargar('pdf') : null,
          ),
          _Formato(
            icono: Icons.table_view_outlined,
            titulo: 'Libro de Excel',
            corto: 'Excel',
            detalle: 'Hoja de resumen y una hoja con el detalle de cada conjunto.',
            generando: _generando == 'xlsx',
            onDescargar: _generando == null && !soloPdf ? () => _descargar('xlsx') : null,
          ),
          _Formato(
            icono: Icons.description_outlined,
            titulo: 'CSV',
            corto: 'CSV',
            detalle: 'Detalle de un conjunto, para analizarlo en otra herramienta.',
            generando: _generando == 'csv',
            onDescargar: _generando == null && !soloPdf ? () => _descargar('csv') : null,
            extra: DropdownButton<String>(
              value: _conjunto,
              onChanged: _generando != null ? null : (v) => setState(() => _conjunto = v!),
              items: [
                for (final MapEntry(:key, :value) in _conjuntos.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _compartir(Uint8List bytes, String nombre, String tipoMime) => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: tipoMime, name: nombre)],
      fileNameOverrides: [nombre],
      downloadFallbackEnabled: true,
    ));

class _Formato extends StatelessWidget {
  const _Formato({
    required this.icono,
    required this.titulo,
    required this.corto,
    required this.detalle,
    required this.generando,
    required this.onDescargar,
    this.extra,
  });

  final IconData icono;
  final String titulo;
  final String corto;
  final String detalle;
  final bool generando;
  final VoidCallback? onDescargar;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: VigiaColors.bosque),
                  const SizedBox(width: 12),
                  Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                ],
              ),
              const SizedBox(height: 6),
              Text(detalle, style: const TextStyle(color: VigiaColors.textoSecundario)),
              ?extra,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onDescargar,
                  icon: generando
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(generando ? 'Generando…' : 'Descargar $corto'),
                ),
              ),
            ],
          ),
        ),
      );
}
