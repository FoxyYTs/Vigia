import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/vigia_marca.dart';
import 'rutas.dart';

/// "Iniciar Sesión" del mapa de navegación. Al entrar lleva al panel con
/// los bloques "Gestionar X"; el Mapa Interactivo es público y no la
/// necesita.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final ancho = c.maxWidth >= 900;
          final formulario = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    if (!ancho) ...[
                      const _PanelMarca(compacto: true),
                      const SizedBox(height: 24),
                    ],
                    const FormularioLogin(),
                    const SizedBox(height: 16),
                    const Text(
                      'Proyecto Integrador · PCJIC 2026',
                      style: TextStyle(color: VigiaColors.textoSecundario, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!ancho) return SafeArea(child: formulario);
          return Row(
            children: [
              const Expanded(child: _PanelMarca()),
              Expanded(child: formulario),
            ],
          );
        },
      ),
    );
  }
}

class _PanelMarca extends StatelessWidget {
  const _PanelMarca({this.compacto = false});

  final bool compacto;

  static const _puntos = [
    (Icons.satellite_alt, 'Focos satelitales de NASA FIRMS e INPE QUEIMADAS', 'Detección térmica sobre el territorio colombiano.'),
    (Icons.photo_camera_outlined, 'Reportes ciudadanos con foto', 'Tomada en el momento y con la ubicación del incendio.'),
    (Icons.notifications_active_outlined, 'Alertas a entidades públicas', 'Para las CAR, los consejos de gestión del riesgo y la ciudadanía.'),
  ];

  @override
  Widget build(BuildContext context) {
    if (compacto) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: VigiaColors.bosque,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VigiaMarca(subtitulo: 'ALERTA TEMPRANA DE INCENDIOS'),
            SizedBox(height: 12),
            Text(
              'Alertas tempranas de incendios forestales en Colombia',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VigiaColors.bosque, Color(0xFF0F3F26)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(56, 56, 56, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VigiaMarca(subtitulo: 'ALERTA TEMPRANA DE INCENDIOS', tamano: 48),
          const SizedBox(height: 32),
          Semantics(
            header: true,
            child: const Text(
              'Alertas tempranas de incendios forestales en Colombia',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, height: 1.2),
            ),
          ),
          const SizedBox(height: 32),
          for (final (icono, titulo, detalle) in _puntos)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Icon(icono, color: const Color(0xFFFFB59B))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titulo,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(detalle, style: const TextStyle(color: Color(0xFFD4EBDC), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          const Text(
            'Proyecto Integrador · Politécnico Colombiano Jaime Isaza Cadavid',
            style: TextStyle(color: Color(0xFFD4EBDC), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Formulario con validación local antes de llamar a la API.
class FormularioLogin extends StatefulWidget {
  const FormularioLogin({super.key});

  @override
  State<FormularioLogin> createState() => _FormularioLoginState();
}

class _FormularioLoginState extends State<FormularioLogin> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  final _focoPassword = FocusNode();
  bool _ocultar = true;

  /// Mismos caracteres que acepta el validador de usernames de Django.
  static final _patronUsuario = RegExp(r'^[\w.@+-]+$');

  static String? validarUsuario(String? valor) {
    final v = valor?.trim() ?? '';
    if (v.isEmpty) return 'Escribe tu nombre de usuario.';
    if (v.length > 150) return 'El usuario no puede tener más de 150 caracteres.';
    if (!_patronUsuario.hasMatch(v)) {
      return 'El usuario solo admite letras, números y los signos @ . + - _';
    }
    return null;
  }

  static String? validarPassword(String? valor) {
    if (valor == null || valor.isEmpty) return 'Escribe tu contraseña.';
    return null;
  }

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    _focoPassword.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final auth = context.read<AuthProvider>();
    if (auth.enviando) return;
    if (!_formKey.currentState!.validate()) return;
    TextInput.finishAutofillContext();
    final ok = await auth.iniciarSesion(_usuario.text, _password.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushNamedAndRemoveUntil(Rutas.panel, (r) => r.settings.name == Rutas.mapa);
    } else {
      _password.clear();
      _focoPassword.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tema = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text('Iniciar sesión',
                      style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Accede para reportar focos y gestionar alertas.',
                  style: TextStyle(color: VigiaColors.textoSecundario),
                ),
                const SizedBox(height: 24),
                if (auth.error != null) ...[
                  _MensajeError(auth.error!),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const Key('campo-usuario'),
                  controller: _usuario,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: validarUsuario,
                  onChanged: (_) => auth.limpiarError(),
                  onFieldSubmitted: (_) => _focoPassword.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('campo-password'),
                  controller: _password,
                  focusNode: _focoPassword,
                  obscureText: _ocultar,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _ocultar = !_ocultar),
                    ),
                  ),
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  validator: validarPassword,
                  onChanged: (_) => auth.limpiarError(),
                  onFieldSubmitted: (_) => _enviar(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('boton-ingresar'),
                  onPressed: auth.enviando ? null : _enviar,
                  icon: auth.enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.login),
                  label: Text(auth.enviando ? 'Ingresando…' : 'Ingresar'),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('o también', style: TextStyle(color: VigiaColors.textoSecundario)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(Rutas.mapa, (_) => false),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Ver el mapa sin iniciar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MensajeError extends StatelessWidget {
  const _MensajeError(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('error-login'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFDAD6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VigiaColors.error),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: VigiaColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(mensaje,
                  style: const TextStyle(color: Color(0xFF7A0E0A), fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
