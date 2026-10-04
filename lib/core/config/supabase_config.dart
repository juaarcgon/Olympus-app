/// Configuración e inicialización del cliente Supabase.
///
/// Lee la URL y la clave anónima del proyecto Supabase desde variables de
/// entorno en tiempo de compilación (`--dart-define`) y expone la función
/// [initSupabase] que arranca el SDK oficial `supabase_flutter`.
///
/// Ejemplo de ejecución con las variables definidas:
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyzcompany.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// URL del proyecto Supabase.
///
/// Se lee de la variable de entorno `SUPABASE_URL` en tiempo de compilación.
/// Por defecto es una cadena vacía cuando no se proporciona.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Clave pública (publishable / anónima) del proyecto Supabase.
///
/// Se lee de la variable de entorno `SUPABASE_ANON_KEY` en tiempo de
/// compilación. Por defecto es una cadena vacía cuando no se proporciona.
///
/// En Supabase esta clave es segura para el cliente; nunca debe usarse aquí la
/// clave secreta.
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Inicializa el cliente Supabase con la URL y la clave anónima configuradas.
///
/// Debe invocarse una sola vez durante el arranque de la aplicación, después de
/// `WidgetsFlutterBinding.ensureInitialized()` y antes de usar
/// `Supabase.instance.client`.
///
/// Lanza [AssertionError] en modo debug si [supabaseUrl] o [supabaseAnonKey]
/// están vacíos, para detectar pronto configuraciones incompletas.
Future<void> initSupabase() async {
  assert(
    supabaseUrl.isNotEmpty,
    'SUPABASE_URL no está definido. Pásalo con '
    '--dart-define=SUPABASE_URL=...',
  );
  assert(
    supabaseAnonKey.isNotEmpty,
    'SUPABASE_ANON_KEY no está definido. Pásalo con '
    '--dart-define=SUPABASE_ANON_KEY=...',
  );

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
}
