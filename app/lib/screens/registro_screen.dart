import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/lista_centrada.dart';
import 'login_screen.dart';
import 'rutas.dart';

/// "Registrar cuenta" (rama de Iniciar Sesión en el mapa de navegación).
/// Siempre crea un ciudadano; administradores y staff los asigna el staff en
/// Gestionar Permisos. La aceptación de la política de datos es expresa
/// (Ley 1581): la casilla arranca sin marcar.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key, this.abrirPolitica});

  /// Inyectable para las pruebas; por defecto abre `privacidad.html`.
  final Future<void> Function()? abrirPolitica;

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _confirmacion = TextEditingController();
  late final Future<List<Municipio>> _municipios = context.read<VigiaApi>().municipios()..ignore();

  String? _departamento;
  int? _municipio;
  bool _acepto = false;
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;

  static final _patronCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    for (final c in [_usuario, _correo, _contrasena, _confirmacion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _abrirPolitica() async {
    if (widget.abrirPolitica != null) return widget.abrirPolitica!();
    // Web: mismo origen que la app; Android: el servidor público.
    await launchUrl(AppConfig.apiBaseUrl.resolve('/privacidad.html'));
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    if (!_acepto) {
      setState(() => _error = 'Debes aceptar la política de tratamiento de datos.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    final api = context.read<VigiaApi>();
    final auth = context.read<AuthProvider>();
    try {
      await api.registrar(
        usuario: _usuario.text.trim(),
        correo: _correo.text.trim(),
        contrasena: _contrasena.text,
        municipio: _municipio,
        aceptoPolitica: _acepto,
      );
      TextInput.finishAutofillContext();
      // Con la cuenta creada se entra de una vez.
      final ok = await auth.iniciarSesion(_usuario.text.trim(), _contrasena.text);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(ok ? Rutas.panel : Rutas.login, (r) => r.settings.name == Rutas.mapa);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar cuenta')),
      body: ListaCentrada(
        maximo: 560,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Crea tu cuenta de ciudadano',
                            style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Con tu cuenta puedes reportar incendios con foto y seguir el estado de tus reportes.',
                        style: TextStyle(color: VigiaColors.textoSecundario),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(_error!, style: const TextStyle(color: VigiaColors.error)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _usuario,
                        decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                        autofillHints: const [AutofillHints.newUsername],
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        validator: FormularioLogin.validarUsuario,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correo,
                        decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            _patronCorreo.hasMatch(v?.trim() ?? '') ? null : 'Escribe un correo válido.',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _contrasena,
                        obscureText: _ocultar,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          helperText: 'Mínimo 8 caracteres, que no sea solo números ni parecida a tu usuario.',
                          helperMaxLines: 2,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _ocultar = !_ocultar),
                          ),
                        ),
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v ?? '').length < 8 ? 'La contraseña debe tener al menos 8 caracteres.' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmacion,
                        obscureText: _ocultar,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (v) => v == _contrasena.text ? null : 'Las contraseñas no coinciden.',
                      ),
                      const SizedBox(height: 12),
                      _SelectorMunicipio(
                        municipios: _municipios,
                        departamento: _departamento,
                        municipio: _municipio,
                        onDepartamento: (d) => setState(() {
                          _departamento = d;
                          _municipio = null;
                        }),
                        onMunicipio: (m) => setState(() => _municipio = m),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _acepto,
                        onChanged: (v) => setState(() => _acepto = v ?? false),
                        title: const Text('Acepto la política de tratamiento de datos personales (Ley 1581 de 2012).'),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _abrirPolitica,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Leer la política de datos'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _enviando ? null : _enviar,
                        icon: _enviando
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(_enviando ? 'Creando cuenta…' : 'Crear cuenta'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Departamento y municipio de residencia (opcional). Si el catálogo no carga,
/// el registro sigue sin municipio.
class _SelectorMunicipio extends StatelessWidget {
  const _SelectorMunicipio({
    required this.municipios,
    required this.departamento,
    required this.municipio,
    required this.onDepartamento,
    required this.onMunicipio,
  });

  final Future<List<Municipio>> municipios;
  final String? departamento;
  final int? municipio;
  final ValueChanged<String?> onDepartamento;
  final ValueChanged<int?> onMunicipio;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Municipio>>(
        future: municipios,
        builder: (context, snap) {
          final lista = snap.data;
          if (lista == null) {
            return Text(
              snap.hasError ? 'No se pudo cargar la lista de municipios; puedes registrarte sin él.' : 'Cargando municipios…',
              style: const TextStyle(color: VigiaColors.textoSecundario),
            );
          }
          final departamentos = {for (final m in lista) m.departamento}.toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: departamento,
                decoration: const InputDecoration(labelText: 'Departamento (opcional)'),
                items: [for (final d in departamentos) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: onDepartamento,
              ),
              if (departamento != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  // La clave reinicia el campo al cambiar de departamento.
                  key: ValueKey(departamento),
                  isExpanded: true,
                  initialValue: municipio,
                  decoration: const InputDecoration(labelText: 'Municipio'),
                  items: [
                    for (final m in lista.where((m) => m.departamento == departamento))
                      DropdownMenuItem(value: m.id, child: Text(m.nombre)),
                  ],
                  onChanged: onMunicipio,
                ),
              ],
            ],
          );
        },
      );
}
