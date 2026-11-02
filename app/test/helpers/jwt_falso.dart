import 'dart:convert';

/// JWT sin firma válida (la app no la verifica: lo hace el backend), con los
/// claims que agrega `TokenVigiaSerializer`.
String jwtFalso({String username = 'ana', String rol = 'ciudadano', Duration vence = const Duration(minutes: 30)}) {
  String b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(vence).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'username': username, 'rol': rol, 'exp': exp})}.firma';
}
