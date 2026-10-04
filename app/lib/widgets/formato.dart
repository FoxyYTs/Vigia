import 'package:intl/intl.dart';

/// Formatos de fecha y número para la interfaz (hora local del navegador o
/// del dispositivo).
class Formato {
  const Formato._();

  static final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
  static final _fecha = DateFormat('dd/MM/yyyy');

  static String fechaHora(DateTime d) => _fechaHora.format(d.toLocal());
  static String fecha(DateTime d) => _fecha.format(d.toLocal());

  /// 1248 → "1.248" (separador de miles colombiano).
  static String entero(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  static String coordenada(double v, {required bool latitud}) {
    final hemisferio = latitud ? (v >= 0 ? 'N' : 'S') : (v >= 0 ? 'E' : 'O');
    return '${v.abs().toStringAsFixed(4).replaceAll('.', ',')}° $hemisferio';
  }
}
