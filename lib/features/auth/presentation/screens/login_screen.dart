// Pantalla de inicio de sesión (Servicio_Autenticacion).
//
// Permite al Usuario introducir su correo electrónico y contraseña e iniciar
// sesión (Req 2.1). Al tener éxito, Supabase emite el cambio de sesión que la
// guarda de enrutado observa para navegar a la zona autenticada; no hace falta
// navegación explícita aquí.
//
// Incluye enlaces a las pantallas de registro y de recuperación de contraseña.
// Los estados de carga y error del `AuthNotifier` se reflejan con un indicador
// de progreso y mensajes en español derivados de `Failure.mensaje`; nunca se
// muestran trazas técnicas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/auth_providers.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Pantalla de inicio de sesión con correo y contraseña (Req 2.1).
class LoginScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de inicio de sesión.
  const LoginScreen({super.key});

  /// Nombre de ruta de la pantalla de inicio de sesión.
  static const String routeName = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Valida el formulario e invoca el inicio de sesión (Req 2.1).
  Future<void> _iniciarSesion() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(authNotifierProvider.notifier)
        .signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;

    // En caso de error se muestra el mensaje; el éxito lo gestiona la guarda de
    // enrutado al reaccionar al cambio de sesión de Supabase.
    final estado = ref.read(authNotifierProvider);
    estado.whenOrNull(
      error: (error, _) =>
          AppNotifications.error(context, _mensajeDeError(error)),
    );
  }

  /// Traduce un error a un mensaje legible en español.
  String _mensajeDeError(Object error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authNotifierProvider);
    final cargando = estado.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailController,
                    enabled: !cargando,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (valor) =>
                        (valor == null || valor.trim().isEmpty)
                        ? 'Introduce tu correo electrónico'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !cargando,
                    obscureText: _ocultarPassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _ocultarPassword = !_ocultarPassword,
                        ),
                        icon: Icon(
                          _ocultarPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => cargando ? null : _iniciarSesion(),
                    validator: (valor) => (valor == null || valor.isEmpty)
                        ? 'Introduce tu contraseña'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: cargando ? null : _iniciarSesion,
                    child: cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: cargando
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('¿No tienes cuenta?'),
                      TextButton(
                        onPressed: cargando
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                        child: const Text('Regístrate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
