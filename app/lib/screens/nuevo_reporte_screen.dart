import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../providers/auth_provider.dart';
import '../widgets/mapa_focos.dart' show limitesColombia;

/// Formulario del reporte ciudadano: foto tomada en el momento (sin galería,
/// DEF-I), ubicación GPS de quien reporta y pin manual del incendio.
/// Devuelve `true` al cerrarse si el reporte se creó.
class NuevoReporteScreen extends StatefulWidget {
  const NuevoReporteScreen({super.key, this.tomarFoto, this.ubicar});

  /// Inyectables para las pruebas; por defecto, cámara y GPS del dispositivo.
  final Future<Uint8List?> Function()? tomarFoto;
  final Future<LatLng> Function()? ubicar;

  @override
  State<NuevoReporteScreen> createState() => _NuevoReporteScreenState();
}

class _NuevoReporteScreenState extends State<NuevoReporteScreen> {
  final _descripcion = TextEditingController();
  final _mapa = MapController();
  Uint8List? _foto;
  LatLng? _usuario;
  LatLng? _incendio;
  String? _error;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _localizar();
  }

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _localizar() async {
    try {
      final posicion = await (widget.ubicar ?? _ubicacionGps)();
      if (!mounted) return;
      setState(() {
        _usuario = posicion;
        _incendio ??= posicion;
        _error = null;
      });
      // El mapa puede no haberse construido aún: se mueve tras el cuadro.
      WidgetsBinding.instance.addPostFrameCallback((_) => _mapa.move(posicion, 13));
    } on _SinUbicacion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _capturar() async {
    try {
      final foto = await (widget.tomarFoto ?? _fotoCamara)();
      if (foto != null && mounted) setState(() => _foto = foto);
    } on Exception {
      // Permiso de cámara negado o dispositivo sin cámara.
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara. Revisa el permiso de cámara de la app.');
    }
  }

  Future<void> _enviar() async {
    final foto = _foto, usuario = _usuario, incendio = _incendio;
    if (foto == null || usuario == null || incendio == null) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final access = await context.read<AuthProvider>().accessToken();
      if (!mounted) return;
      await context.read<VigiaApi>().crearReporte(
            access,
            foto: foto,
            ubicacionUsuario: usuario,
            ubicacionIncendio: incendio,
            descripcion: _descripcion.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte enviado. Una entidad lo revisará.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listo = _foto != null && _usuario != null && _incendio != null && !_enviando;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo reporte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Paso('1. Foto del incendio', 'Tómala ahora con la cámara; no se aceptan fotos de la galería.'),
          // En el navegador de escritorio el selector puede abrir archivos:
          // el servidor revisa la fecha y el GPS de la foto (EXIF).
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Desde el navegador se puede elegir un archivo; la fecha y la ubicación de la foto se revisan al validar.',
                style: TextStyle(color: VigiaColors.textoSecundario, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          if (_foto != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_foto!, height: 220, fit: BoxFit.cover, semanticLabel: 'Foto tomada'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : _capturar,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_foto == null ? 'Tomar foto' : 'Repetir foto'),
            ),
          ),
          const SizedBox(height: 20),
          const _Paso('2. ¿Dónde está el incendio?',
              'Toca el mapa para mover el pin. Puedes reportar desde lejos: tu ubicación se guarda aparte.'),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                mapController: _mapa,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(bounds: limitesColombia),
                  onTap: _enviando ? null : (_, punto) => setState(() => _incendio = punto),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vigia.foxyyts',
                  ),
                  MarkerLayer(markers: [
                    if (_usuario != null)
                      Marker(
                        point: _usuario!,
                        child: const Icon(Icons.my_location, color: VigiaColors.bosque, semanticLabel: 'Tu ubicación'),
                      ),
                    if (_incendio != null)
                      Marker(
                        point: _incendio!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, size: 40, color: VigiaColors.fuego,
                            semanticLabel: 'Ubicación del incendio'),
                      ),
                  ]),
                  // Exigido por la política de uso de las teselas de OpenStreetMap.
                  const RichAttributionWidget(
                    alignment: AttributionAlignment.bottomLeft,
                    attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                  ),
                ],
              ),
            ),
          ),
          if (_usuario == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Obteniendo tu ubicación…', style: TextStyle(color: VigiaColors.textoSecundario)),
            ),
          const SizedBox(height: 20),
          const _Paso('3. Descripción (opcional)', 'Qué ves: humo, llamas, tamaño aproximado, accesos.'),
          const SizedBox(height: 8),
          TextField(
            controller: _descripcion,
            maxLength: 2000,
            maxLines: 3,
            enabled: !_enviando,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: VigiaColors.error)),
            if (_usuario == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _localizar, child: const Text('Reintentar ubicación')),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: listo ? _enviar : null,
            icon: _enviando
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso(this.titulo, this.detalle);

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Text(detalle, style: const TextStyle(color: VigiaColors.textoSecundario, fontSize: 13)),
        ],
      );
}

class _SinUbicacion implements Exception {
  const _SinUbicacion(this.mensaje);

  final String mensaje;
}

Future<LatLng> _ubicacionGps() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const _SinUbicacion('Activa la ubicación del dispositivo para reportar.');
  }
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
  if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
    throw const _SinUbicacion('Vigía necesita tu ubicación para recibir el reporte.');
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    return LatLng(p.latitude, p.longitude);
  } on Exception {
    throw const _SinUbicacion('No se pudo obtener tu ubicación. Inténtalo de nuevo.');
  }
}

/// Solo cámara. La reducción a 1920 px deja la foto muy por debajo del
/// límite de 5 MB del backend sin perder detalle útil.
Future<Uint8List?> _fotoCamara() async {
  final foto = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1920,
    maxHeight: 1920,
    imageQuality: 80,
  );
  return foto?.readAsBytes();
}
