// Configuración compartida para las pruebas de INTEGRACIÓN de seguridad y del
// flujo de restablecimiento (tarea 12.3).
//
// Lee la conexión a Supabase desde el entorno de compilación (`--dart-define`)
// y expone un interruptor para OMITIR los grupos de integración cuando no hay
// backend configurado, de modo que `flutter test` siga en verde en CI/entornos
// sin Supabase. Mismo patrón que `reservas_rpc_integracion_test.dart`.

/// Interruptor maestro: si no es `true`, se OMITEN los grupos de integración.
const bool kRunIntegration = bool.fromEnvironment(
  'INTEGRATION_SUPABASE',
  defaultValue: false,
);

/// URL de la API del proyecto Supabase (p. ej. `http://127.0.0.1:54321`).
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Clave anónima (publishable) del proyecto Supabase.
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Clave de servicio (service role) para operaciones de administración en las
/// pruebas (crear usuarios, fijar roles, leer sin RLS). NUNCA se usa en la app
/// real; solo en el arnés de pruebas de integración.
const String kSupabaseServiceRoleKey = String.fromEnvironment(
  'SUPABASE_SERVICE_ROLE_KEY',
);

/// Caducidad esperada del `Token_Restablecimiento`, en segundos (Req 9.3): 60
/// minutos. Debe coincidir con la expiración configurada en Supabase Auth
/// (`[auth.email] otp_expiry` / "mailer OTP exp"). Se puede sobreescribir con
/// `--dart-define=RESET_TOKEN_EXPIRY_SECONDS=<n>` si el proyecto lo configura
/// de otro modo, para que la prueba (d) compruebe el valor realmente aplicado.
const int kExpiracionResetSegundos = int.fromEnvironment(
  'RESET_TOKEN_EXPIRY_SECONDS',
  defaultValue: 3600,
);

/// Indica si hay configuración suficiente para ejecutar la integración.
bool get integracionDisponible =>
    kRunIntegration &&
    kSupabaseUrl.isNotEmpty &&
    kSupabaseAnonKey.isNotEmpty &&
    kSupabaseServiceRoleKey.isNotEmpty;

/// Razón de omisión mostrada cuando falta configuración (o `false` si procede
/// ejecutar). Compatible con el parámetro `skip` de `test`.
dynamic get skipReason => integracionDisponible
    ? false
    : 'Pruebas de integración de seguridad omitidas: requieren una instancia '
          'de Supabase en marcha. Ejecuta con '
          '--dart-define=INTEGRATION_SUPABASE=true y las claves '
          'SUPABASE_URL/SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY (ver '
          'README de test/features/security/).';
