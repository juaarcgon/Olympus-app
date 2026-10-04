// Contrato de dominio del Servicio_Autenticacion.
//
// Define la interfaz `AuthRepository` que la capa de presentación consume para
// registrar usuarios, iniciar/cerrar sesión, solicitar el restablecimiento de
// contraseña y observar los cambios de sesión. La implementación concreta
// (`AuthRepositoryImpl`, tarea 6.2) vive en la capa de datos y traduce los
// errores de Supabase Auth a la jerarquía `Failure` del dominio.
//
// Trazabilidad de requisitos:
// - Req 1.1/1.3: alta de usuario con nombre/apellidos; credenciales gestionadas
//   por Auth (hashing delegado).
// - Req 2.1/2.4/2.5: inicio y cierre de sesión.
// - Req 7.1: las credenciales nunca se manejan en texto plano por el cliente.
// - Req 9.2/9.7: recuperación de contraseña (envío de enlace y actualización
//   con el token de la sesión de recuperación).
//
// Ref. diseño: "Servicio_Autenticacion".

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'package:olympus/features/auth/domain/entities/app_user.dart';

/// Puerto de dominio para la autenticación de usuarios (Servicio_Autenticacion).
///
/// Expone las operaciones de alta, inicio/cierre de sesión y recuperación de
/// contraseña, además de un flujo de cambios de sesión. Las implementaciones
/// validan las entradas (Req 1.5/1.6) y traducen los errores del proveedor de
/// autenticación a tipos `Failure` del dominio.
abstract class AuthRepository {
  /// Registra un nuevo Usuario y devuelve su perfil de dominio.
  ///
  /// El [nombre] y los [apellidos] se envían como metadata del alta para que el
  /// trigger de backend complete la fila de `profiles` (Req 1.1). La [foto]
  /// opcional se asocia como `foto_url` si se proporciona (Req 1.7). Las
  /// credenciales ([email]/[password]) las gestiona el proveedor de Auth, que
  /// aplica el hashing y controla el email duplicado (Req 1.3, 1.4).
  Future<AppUser> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
    XFile? foto,
  });

  /// Inicia sesión con [email] y [password] y devuelve el perfil autenticado.
  ///
  /// Establece la sesión del Usuario (Req 2.1). Las implementaciones traducen
  /// las credenciales inválidas (Req 2.2) y las cuentas suspendidas (Req 2.3) a
  /// los `Failure` correspondientes.
  Future<AppUser> signIn({required String email, required String password});

  /// Cierra la sesión activa del Usuario (Req 2.4).
  Future<void> signOut();

  /// Solicita el restablecimiento de la contraseña asociada a [email].
  ///
  /// Envía el enlace de recuperación (Req 9.2). Por seguridad la respuesta es
  /// siempre genérica, sin revelar si el email existe (Req 9.1).
  Future<void> requestPasswordReset(String email);

  /// Fija la [newPassword] del Usuario dentro de la sesión de recuperación.
  ///
  /// Se invoca tras abrir el enlace de restablecimiento, cuando existe una
  /// sesión de recuperación válida (Req 9.7). La [newPassword] debe cumplir la
  /// longitud mínima (Req 9.6), validada por la implementación.
  Future<void> updatePasswordWithToken(String newPassword);

  /// Flujo de los cambios de estado de autenticación (Req 7.3).
  ///
  /// Emite un [AuthState] cada vez que la sesión cambia (inicio de sesión,
  /// cierre, refresco de token o inicio de recuperación), permitiendo que el
  /// enrutado reaccione entre las zonas pública y autenticada.
  Stream<AuthState> authStateChanges();
}
