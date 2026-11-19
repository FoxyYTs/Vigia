/// DTO de `/api/bot-telegram/` (apps/notificaciones/views.py).
class EstadoBot {
  const EstadoBot({required this.bot, required this.tokenConfigurado, required this.canales, required this.recientes});

  /// Nombre del bot según Telegram, o null si no responde o no hay token.
  final String? bot;
  final bool tokenConfigurado;
  final List<CanalBot> canales;
  final List<EnvioBot> recientes;

  String nombreCanal(String canal) =>
      canales.where((c) => c.canal == canal).map((c) => c.nombre).firstOrNull ?? canal;

  factory EstadoBot.fromJson(Map<String, dynamic> json) => EstadoBot(
        bot: json['bot'] as String?,
        tokenConfigurado: json['token_configurado'] as bool,
        canales: [for (final c in (json['canales'] as List).cast<Map<String, dynamic>>()) CanalBot.fromJson(c)],
        recientes: [for (final n in (json['recientes'] as List).cast<Map<String, dynamic>>()) EnvioBot.fromJson(n)],
      );
}

class CanalBot {
  const CanalBot({
    required this.canal,
    required this.nombre,
    required this.configurado,
    required this.alertas,
    required this.enviados7d,
    required this.fallidos7d,
    required this.ultimoEnvio,
  });

  final String canal;
  final String nombre;
  final bool configurado;

  /// Tipos de alerta (`Alerta.TipoDisparador`) que recibe el canal.
  final List<String> alertas;
  final int enviados7d;
  final int fallidos7d;
  final DateTime? ultimoEnvio;

  factory CanalBot.fromJson(Map<String, dynamic> json) => CanalBot(
        canal: json['canal'] as String,
        nombre: json['nombre'] as String,
        configurado: json['configurado'] as bool,
        alertas: (json['alertas'] as List).cast<String>(),
        enviados7d: json['enviados_7d'] as int,
        fallidos7d: json['fallidos_7d'] as int,
        ultimoEnvio: json['ultimo_envio'] == null ? null : DateTime.parse(json['ultimo_envio'] as String),
      );
}

class EnvioBot {
  const EnvioBot({
    required this.fechaEnvio,
    required this.canal,
    required this.estado,
    required this.tipoAlerta,
    required this.municipio,
  });

  final DateTime fechaEnvio;
  final String canal;
  final String estado;
  final String tipoAlerta;
  final String? municipio;

  bool get fallido => estado == 'fallido';

  factory EnvioBot.fromJson(Map<String, dynamic> json) => EnvioBot(
        fechaEnvio: DateTime.parse(json['fecha_envio'] as String),
        canal: json['canal'] as String,
        estado: json['estado'] as String,
        tipoAlerta: json['tipo_alerta'] as String,
        municipio: json['municipio'] as String?,
      );
}
