// Pantalla de perfil del Usuario (Servicio_Usuarios).
//
// Muestra los datos del perfil del Usuario autenticado y permite editar los
// campos editables:
//
//   - Lectura (Req 3.1): nombre, apellidos, correo electrónico, foto y
//     Saldo_De_Clases. El saldo y el estado se muestran en SOLO LECTURA; esta
//     pantalla no ofrece ningún control para modificarlos (Req 3.3, 3.4).
//   - Edición (Req 3.2): campos de texto para nombre y apellidos, y un botón
//     basado en `image_picker` para elegir una nueva foto; un botón de guardar
//     invoca al `ProfileNotifier`.
//
// Los estados de carga y error del provider se reflejan con un indicador de
// progreso y mensajes en español; nunca se muestran trazas técnicas.

import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failures.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/profile.dart';
import '../providers/profile_providers.dart';

/// Pantalla que muestra y permite editar el perfil del Usuario autenticado.
class ProfileScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de perfil.
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _imagePicker = ImagePicker();

  /// Foto recién seleccionada pendiente de guardar; `null` si no se cambió.
  XFile? _fotoSeleccionada;

  /// Indica si los controladores ya se inicializaron con el perfil cargado,
  /// para no sobrescribir lo que el Usuario esté escribiendo en recargas.
  bool _camposInicializados = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    super.dispose();
  }

  /// Rellena los campos del formulario con los valores del perfil una sola vez.
  void _inicializarCampos(Profile profile) {
    if (_camposInicializados) return;
    _nombreController.text = profile.nombre;
    _apellidosController.text = profile.apellidos;
    _camposInicializados = true;
  }

  /// Abre la galería para elegir una nueva foto de perfil (Req 3.2 / 1.7).
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
      _mostrarMensaje('No se pudo seleccionar la imagen');
    }
  }

  /// Valida el formulario y envía los cambios al `ProfileNotifier` (Req 3.2).
  Future<void> _guardar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(profileNotifierProvider.notifier)
        .updateProfile(
          nombre: _nombreController.text.trim(),
          apellidos: _apellidosController.text.trim(),
          foto: _fotoSeleccionada,
        );

    if (!mounted) return;

    final estado = ref.read(profileNotifierProvider);
    estado.when(
      data: (_) {
        setState(() => _fotoSeleccionada = null);
        _mostrarMensaje('Perfil actualizado correctamente');
      },
      loading: () {},
      error: (error, _) => _mostrarMensaje(_mensajeDeError(error)),
    );
  }

  /// Muestra un `SnackBar` con un mensaje en español.
  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Traduce un error a un mensaje legible en español.
  String _mensajeDeError(Object error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  /// Cierra la sesión del Usuario (Req 2.4).
  ///
  /// La guarda de enrutado reacciona al cambio de sesión de Supabase para
  /// volver a la zona pública; aquí solo se delega en el `AuthNotifier`.
  Future<void> _cerrarSesion() async {
    await ref.read(authNotifierProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final estadoPerfil = ref.watch(profileNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: estadoPerfil.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPerfil(
          mensaje: _mensajeDeError(error),
          onReintentar: () =>
              ref.read(profileNotifierProvider.notifier).refresh(),
        ),
        data: (profile) {
          _inicializarCampos(profile);
          // `isLoading` es true durante una actualización en curso (Req 3.2).
          final guardando = estadoPerfil.isLoading;
          return _FormularioPerfil(
            formKey: _formKey,
            profile: profile,
            nombreController: _nombreController,
            apellidosController: _apellidosController,
            fotoSeleccionada: _fotoSeleccionada,
            guardando: guardando,
            onSeleccionarFoto: _seleccionarFoto,
            onGuardar: _guardar,
          );
        },
      ),
    );
  }
}

/// Vista de error con opción de reintentar la carga del perfil.
class _ErrorPerfil extends StatelessWidget {
  const _ErrorPerfil({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulario de edición del perfil con la foto, los campos editables y el
/// saldo en solo lectura.
class _FormularioPerfil extends StatelessWidget {
  const _FormularioPerfil({
    required this.formKey,
    required this.profile,
    required this.nombreController,
    required this.apellidosController,
    required this.fotoSeleccionada,
    required this.guardando,
    required this.onSeleccionarFoto,
    required this.onGuardar,
  });

  final GlobalKey<FormState> formKey;
  final Profile profile;
  final TextEditingController nombreController;
  final TextEditingController apellidosController;
  final XFile? fotoSeleccionada;
  final bool guardando;
  final VoidCallback onSeleccionarFoto;
  final Future<void> Function() onGuardar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _AvatarPerfil(
                fotoUrl: profile.fotoUrl,
                fotoSeleccionada: fotoSeleccionada,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: guardando ? null : onSeleccionarFoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Cambiar foto'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: nombreController,
              enabled: !guardando,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'El nombre es obligatorio'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: apellidosController,
              enabled: !guardando,
              decoration: const InputDecoration(
                labelText: 'Apellidos',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'Los apellidos son obligatorios'
                  : null,
            ),
            const SizedBox(height: 16),
            // Correo electrónico: solo lectura (espejo de la cuenta de Auth).
            _CampoSoloLectura(
              etiqueta: 'Correo electrónico',
              valor: profile.email,
              icono: Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            // Saldo de clases: SOLO LECTURA (Req 3.1, 3.3). El Usuario estándar
            // no puede modificar su saldo desde esta pantalla.
            _CampoSoloLectura(
              etiqueta: 'Saldo de clases',
              valor: '${profile.saldoClases}',
              icono: Icons.confirmation_number_outlined,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: guardando ? null : () => onGuardar(),
              child: guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar circular que muestra la foto seleccionada pendiente de guardar, en su
/// defecto la foto actual del perfil, o un icono genérico.
class _AvatarPerfil extends StatelessWidget {
  const _AvatarPerfil({required this.fotoUrl, required this.fotoSeleccionada});

  final String? fotoUrl;
  final XFile? fotoSeleccionada;

  @override
  Widget build(BuildContext context) {
    const double radio = 56;
    ImageProvider? imagen;

    if (fotoSeleccionada != null && !kIsWeb) {
      imagen = FileImage(File(fotoSeleccionada!.path));
    } else if (fotoSeleccionada != null) {
      imagen = NetworkImage(fotoSeleccionada!.path);
    } else if (fotoUrl != null && fotoUrl!.isNotEmpty) {
      imagen = NetworkImage(fotoUrl!);
    }

    return CircleAvatar(
      radius: radio,
      backgroundImage: imagen,
      child: imagen == null ? const Icon(Icons.person, size: radio) : null,
    );
  }
}

/// Campo de visualización en solo lectura con etiqueta e icono.
class _CampoSoloLectura extends StatelessWidget {
  const _CampoSoloLectura({
    required this.etiqueta,
    required this.valor,
    required this.icono,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icono),
        enabled: false,
      ),
      child: Text(valor),
    );
  }
}
