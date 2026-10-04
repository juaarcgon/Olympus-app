// Data source remoto de autenticación (Supabase Auth).
//
// Encapsula las llamadas directas al cliente de `supabase_flutter` para la
// feature de autenticación. Es una capa delgada y sin lógica de negocio: no
// valida entradas ni traduce errores (eso corresponde a `AuthRepositoryImpl`,
// tarea 6.2). Simplemente adapta el SDK para que el resto del dominio no
// dependa de él directamente.
//
// Trazabilidad de requisitos:
// - Req 1.1/1.3: alta con metadata nombre/apellidos (consumida por el trigger
//   de backend) y credenciales gestionadas por Auth.
// - Req 2.1/2.4/2.5: inicio y cierre de sesión.
// - Req 9.2: envío del enlace de restablecimiento.
// - Req 9.7: actualización de la contraseña dentro de la sesión de recuperación.
//
// Ref. diseño: "Servicio_Autenticacion".

import 'package:supabase_flutter/supabase_flutter.dart';

/// Claves de la metadata de usuario enviada en el alta.
///
/// El trigger `on_auth_user_created` del backend lee estos campos para poblar
/// las columnas `nombre` y `apellidos` de `profiles` (Req 1.1).
const String kMetadataNombre = 'nombre';

/// Clave de los apellidos dentro de la metadata de usuario del alta (Req 1.1).
const String kMetadataApellidos = 'apellidos';

/// Acceso de bajo nivel a Supabase Auth para la feature de autenticación.
///
/// Delega directamente en `GoTrueClient`. Las excepciones del SDK (como
/// `AuthException`) se propagan sin modificar para que la capa de repositorio
/// las traduzca a la jerarquía `Failure` del dominio.
class AuthRemoteDataSource {
  /// Crea el data source sobre un [SupabaseClient].
  ///
  /// Si no se proporciona [client], se usa la instancia global ya inicializada
  /// por `initSupabase()`.
  AuthRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Cliente de autenticación subyacente de Supabase.
  GoTrueClient get _auth => _client.auth;

  /// Registra un nuevo usuario en Supabase Auth (Req 1.1, 1.3).
  ///
  /// Envía [nombre] y [apellidos] como `data` (metadata del usuario) para que
  /// el trigger de backend complete su fila en `profiles`. El [email] y la
  /// [password] los gestiona Auth, que aplica el hashing y rechaza emails
  /// duplicados (Req 1.4).
  Future<AuthResponse> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        kMetadataNombre: nombre,
        kMetadataApellidos: apellidos,
      },
    );
  }

  /// Inicia sesión con email y contraseña (Req 2.1).
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  /// Cierra la sesión activa del usuario (Req 2.4).
  Future<void> signOut() => _auth.signOut();

  /// Envía el enlace de restablecimiento de contraseña al [email] (Req 9.2).
  Future<void> resetPasswordForEmail(String email) {
    return _auth.resetPasswordForEmail(email);
  }

  /// Actualiza la contraseña del usuario en la sesión actual (Req 9.7).
  ///
  /// Se invoca dentro de la sesión de recuperación abierta por el enlace de
  /// restablecimiento.
  Future<UserResponse> updatePassword(String newPassword) {
    return _auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Flujo de cambios de estado de autenticación del SDK (Req 7.3).
  Stream<AuthState> authStateChanges() => _auth.onAuthStateChange;
}
