// Pantalla de registro de nuevos usuarios (Servicio_Autenticacion).
//
// Recoge nombre, apellidos, correo electrónico y contraseña, además de una foto
// de perfil opcional seleccionada con `image_picker` (Req 1.1, 1.7). Al
// registrarse con éxito, Supabase emite el cambio de sesión que la guarda de
// enrutado observa para navegar a la zona autenticada.
//
// La contraseña debe tener al menos ocho (8) caracteres; se muestra una pista
// y se valida en el cliente (Req 9.6 / 1.6). Los estados de carga y error del
// `AuthNotifier` se reflejan con un indicador de progreso y mensajes en español
// derivados de `Failure.mensaje`.

import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/auth_providers.dart';

/// Longitud mínima de la contraseña mostrada como pista al Usuario (Req 9.6).
const int _passwordMinLength = 8;

/// Pantalla de alta de un nuevo Usuario (Req 1.1).
class RegisterScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de registro.
  const RegisterScreen({super.key});

  /// Nombre de ruta de la pantalla de registro.
  static const String routeName = '/register';

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _ocultarPassword = true;

  /// Foto seleccionada para el nuevo perfil; `null` si no se eligió ninguna.
  XFile? _fotoSeleccionada;

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Abre la galería para elegir una foto de perfil opcional (Req 1.7).
  Future<void> _seleccionarFoto() async {
    try {
      final foto = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (foto != null) {
        setState(() => _fotoSeleccionada = foto);
      }
    } on Object {
      if (!mounted) return;
      AppNotifications.error(context, 'No se pudo seleccionar la imagen');
    }
  }

  /// Valida el formulario e invoca el registro (Req 1.1, 1.7).
  Future<void> _registrar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    try {
      final resultado = await ref
          .read(authNotifierProvider.notifier)
          .signUp(
            nombre: _nombreController.text.trim(),
            apellidos: _apellidosController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            foto: _fotoSeleccionada,
          );

      if (!mounted) return;

      // En ambos desenlaces se cierra la pantalla de registro para que el shell
      // de enrutado quede visible. Con sesión activa, la guarda muestra la zona
      // autenticada; si quedó pendiente de confirmación, se vuelve al login y
      // se avisa al Usuario de que revise su correo.
      if (resultado == SignUpResult.confirmacionPendiente) {
        AppNotifications.exito(
          context,
          'Cuenta creada. Revisa tu correo para confirmarla antes de '
          'iniciar sesión.',
        );
      }
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, _mensajeDeError(error));
    }
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
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _AvatarRegistro(fotoSeleccionada: _fotoSeleccionada),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: cargando ? null : _seleccionarFoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Añadir foto (opcional)'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombreController,
                  enabled: !cargando,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (valor) => (valor == null || valor.trim().isEmpty)
                      ? 'El nombre es obligatorio'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apellidosController,
                  enabled: !cargando,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (valor) => (valor == null || valor.trim().isEmpty)
                      ? 'Los apellidos son obligatorios'
                      : null,
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
                  textInputAction: TextInputAction.next,
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Introduce tu correo electrónico';
                    }
                    return esEmailValido(valor)
                        ? null
                        : 'El formato del correo electrónico no es válido';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !cargando,
                  obscureText: _ocultarPassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Mínimo $_passwordMinLength caracteres',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _ocultarPassword = !_ocultarPassword),
                      icon: Icon(
                        _ocultarPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (valor) {
                    if (valor == null || valor.isEmpty) {
                      return 'Introduce una contraseña';
                    }
                    return esPasswordValida(valor)
                        ? null
                        : 'La contraseña debe tener al menos '
                              '$_passwordMinLength caracteres';
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: cargando ? null : _registrar,
                  child: cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear cuenta'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: cargando
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Ya tengo cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar circular que muestra la foto seleccionada o un icono genérico.
class _AvatarRegistro extends StatelessWidget {
  const _AvatarRegistro({required this.fotoSeleccionada});

  final XFile? fotoSeleccionada;

  @override
  Widget build(BuildContext context) {
    const double radio = 48;
    ImageProvider? imagen;

    if (fotoSeleccionada != null && !kIsWeb) {
      imagen = FileImage(File(fotoSeleccionada!.path));
    } else if (fotoSeleccionada != null) {
      imagen = NetworkImage(fotoSeleccionada!.path);
    }

    return CircleAvatar(
      radius: radio,
      backgroundImage: imagen,
      child: imagen == null ? const Icon(Icons.person, size: radio) : null,
    );
  }
}
