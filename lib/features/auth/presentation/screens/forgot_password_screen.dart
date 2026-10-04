// Pantalla de solicitud de restablecimiento de contraseña (Servicio_Autenticacion).
//
// Recoge el correo electrónico del Usuario e invoca
// `AuthNotifier.requestPasswordReset` (Req 9.2). Por seguridad, al completarse
// la operación SIEMPRE se muestra el mismo mensaje genérico, con independencia
// de si el correo está asociado a una cuenta (Req 9.1): nunca se revela la
// existencia del email.
//
// Los estados de carga se reflejan con un indicador de progreso; los mensajes
// se muestran en español.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/widgets.dart';
import '../providers/auth_providers.dart';

/// Mensaje genérico mostrado tras solicitar el restablecimiento (Req 9.1).
const String _mensajeGenerico =
    'Si el correo electrónico existe, se ha enviado un enlace de '
    'restablecimiento.';

/// Pantalla para solicitar el enlace de recuperación de contraseña (Req 9.1).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de recuperación de contraseña.
  const ForgotPasswordScreen({super.key});

  /// Nombre de ruta de la pantalla de recuperación de contraseña.
  static const String routeName = '/forgot-password';

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  /// Indica si ya se envió la solicitud, para mostrar el mensaje genérico.
  bool _solicitado = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Valida el formulario e invoca la solicitud de restablecimiento (Req 9.2).
  ///
  /// Independientemente del resultado interno, se muestra el mensaje genérico
  /// (Req 9.1): la operación nunca revela si el correo existe.
  Future<void> _solicitar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(authNotifierProvider.notifier)
        .requestPasswordReset(_emailController.text.trim());

    if (!mounted) return;
    setState(() => _solicitado = true);
    AppNotifications.exito(context, _mensajeGenerico);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authNotifierProvider);
    final cargando = estado.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Introduce tu correo electrónico y te enviaremos un enlace '
                  'para restablecer tu contraseña.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  enabled: !cargando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (valor) => (valor == null || valor.trim().isEmpty)
                      ? 'Introduce tu correo electrónico'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: cargando ? null : _solicitar,
                  child: cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enviar enlace'),
                ),
                if (_solicitado) ...[
                  const SizedBox(height: 24),
                  const Text(_mensajeGenerico, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: cargando
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Volver al inicio de sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
