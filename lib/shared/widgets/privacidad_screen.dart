// Pantalla "Privacidad y protección de datos".
//
// Informa a los socios, en lenguaje claro, de qué datos personales trata la
// app, para qué, quién puede verlos y cómo ejercer sus derechos (RGPD/LOPDGDD).
// En particular explica que el nombre y los apellidos de cada socio son
// visibles para los demás socios en la lista de apuntados de las clases a las
// que se apunta (RPC `apuntados_clase`, migración 0014).
//
// Se abre desde el registro y desde "Mi perfil". Es accesible sin sesión.
//
// IMPORTANTE: los datos del responsable del tratamiento (constantes `kPrivacidad*`
// de abajo) deben completarse con los datos reales del gimnasio antes de
// distribuir la app, y el texto conviene que lo revise alguien con conocimientos
// de protección de datos.

import 'package:flutter/material.dart';

// --- Datos del responsable del tratamiento: COMPLETAR antes de publicar -----

/// Nombre o razón social del gimnasio (responsable del tratamiento).
const String kPrivacidadResponsable = '[Nombre o razón social del gimnasio]';

/// NIF/CIF del responsable.
const String kPrivacidadNif = '[NIF/CIF]';

/// Dirección postal del responsable.
const String kPrivacidadDireccion = '[Dirección postal]';

/// Correo de contacto para cuestiones de privacidad y ejercicio de derechos.
const String kPrivacidadEmail = '[correo de contacto]';

/// Base jurídica del tratamiento.
const String kPrivacidadBaseLegal = '[Base jurídica del tratamiento]';

/// Plazo de conservación de los datos tras darse de baja.
const String kPrivacidadConservacion = '[plazo de conservación tras la baja]';

/// Fecha de la última actualización de este texto.
const String kPrivacidadActualizacion = 'noviembre de 2026';

// -----------------------------------------------------------------------------

/// Pantalla con la información de privacidad y protección de datos.
class PrivacidadScreen extends StatelessWidget {
  /// Crea la pantalla de privacidad.
  const PrivacidadScreen({super.key});

  /// Abre la pantalla de privacidad sobre la ruta actual.
  static Future<void> abrir(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PrivacidadScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Privacidad y protección de datos',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Última actualización: $kPrivacidadActualizacion',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            // Lo más importante primero y destacado: la visibilidad del nombre.
            const _Destacado(
              titulo: 'Tu nombre es visible para otros socios',
              texto:
                  'Cuando te apuntas a una clase, los demás socios que usan la '
                  'app pueden ver tu nombre y apellidos en la lista de '
                  'apuntados de esa clase. Si estás en la lista de espera, '
                  'también ven tu posición. No ven tu correo, tu foto, tu '
                  'saldo de clases ni ningún otro dato.',
            ),
            const _Seccion(
              titulo: 'Responsable del tratamiento',
              parrafos: [
                '$kPrivacidadResponsable\n'
                    'NIF/CIF: $kPrivacidadNif\n'
                    '$kPrivacidadDireccion\n'
                    'Contacto: $kPrivacidadEmail',
              ],
            ),
            const _Seccion(
              titulo: 'Qué datos tratamos',
              parrafos: [
                '• Nombre y apellidos.\n'
                    '• Correo electrónico.\n'
                    '• Foto de perfil, si decides añadirla.\n'
                    '• Saldo de clases de tu bono.\n'
                    '• Tus reservas y tus entradas en listas de espera.\n'
                    '• Un identificador técnico de tu móvil para enviarte '
                    'notificaciones, si las permites. Se borra al cerrar '
                    'sesión.',
              ],
            ),
            const _Seccion(
              titulo: 'Para qué los usamos',
              parrafos: [
                'Para gestionar tu cuenta de socio, tu bono de clases y tus '
                    'reservas, para enviarte los correos necesarios de la '
                    'cuenta (por ejemplo, para recuperar la contraseña) y, si '
                    'lo permites, para avisarte en el móvil cuando consigues '
                    'plaza desde la lista de espera. Puedes desactivar las '
                    'notificaciones cuando quieras en los ajustes del móvil.',
                'Base jurídica: $kPrivacidadBaseLegal.',
              ],
            ),
            const _Seccion(
              titulo: 'Quién puede ver tus datos',
              parrafos: [
                'Otros socios: solo tu nombre y apellidos, y tu posición en la '
                    'lista de espera, en las clases a las que te apuntas.',
                'Administración del gimnasio: tu perfil, tu bono y tus '
                    'reservas, para gestionar el servicio.',
                'Proveedores tecnológicos que prestan el servicio por cuenta '
                    'del gimnasio: alojamiento y base de datos (Supabase), '
                    'envío de correos electrónicos y envío de notificaciones '
                    'al móvil (Google Firebase). Solo tratan los datos para '
                    'prestar ese servicio.',
              ],
            ),
            const _Seccion(
              titulo: 'Cuánto tiempo los conservamos',
              parrafos: [
                'Mientras mantengas tu cuenta de socio. Tras la baja, '
                    '$kPrivacidadConservacion.',
              ],
            ),
            const _Seccion(
              titulo: 'Tus derechos',
              parrafos: [
                'Puedes acceder a tus datos, rectificarlos, pedir su '
                    'supresión, oponerte a su tratamiento, solicitar su '
                    'limitación o su portabilidad escribiendo a '
                    '$kPrivacidadEmail.',
                'Tu nombre, apellidos y foto puedes cambiarlos directamente '
                    'desde "Mi perfil".',
                'Si consideras que no hemos tratado bien tus datos, puedes '
                    'reclamar ante la Agencia Española de Protección de Datos '
                    '(www.aepd.es).',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloque destacado para la información más relevante para el socio.
class _Destacado extends StatelessWidget {
  const _Destacado({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    texto,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sección con título y uno o varios párrafos.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.parrafos});

  final String titulo;
  final List<String> parrafos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          for (final parrafo in parrafos) ...[
            const SizedBox(height: 8),
            Text(parrafo),
          ],
        ],
      ),
    );
  }
}
