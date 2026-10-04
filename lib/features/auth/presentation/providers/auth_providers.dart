// Providers de Riverpod para el Servicio_Autenticacion.
//
// Esta capa de estado (Application) orquesta los casos de uso de autenticación
// sobre el [AuthRepository] de dominio y expone estados inmutables de carga/
// éxito/error que la UI observa:
//
//   - [authRepositoryProvider]: inyecta la implementación concreta del
//     repositorio ([AuthRepositoryImpl]) de forma testable (se puede
//     sobrescribir en pruebas con `overrideWithValue`).
//   - [AuthNotifier] / [authNotifierProvider]: `AsyncNotifier` que orquesta el
//     registro (Req 1.1), el inicio de sesión (Req 2.1), el cierre de sesión
//     (Req 2.4), la solicitud de restablecimiento (Req 9.1/9.2) y la fijación
//     de la nueva contraseña (Req 9.6/9.7), reflejando los estados de carga y
//     error en cada operación.
//   - [authStateChangesProvider]: flujo de los cambios de sesión de Supabase,
//     útil para que la guarda de enrutado reaccione entre las zonas pública y
//     autenticada (Req 7.3).
//
// Ref. diseño: "Servicio_Autenticacion"; "Capas del cliente Flutter".

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Desenlace de una operación de registro correcta.
enum SignUpResult {
  /// El alta dejó una sesión activa: el enrutado navega a la zona autenticada.
  sesionIniciada,

  /// El alta requiere confirmar el correo: aún no hay sesión. La UI debe
  /// informar al Usuario de que revise su bandeja de entrada.
  confirmacionPendiente,
}

/// Provee la implementación del [AuthRepository] (Servicio_Autenticacion).
///
/// Por defecto construye un [AuthRepositoryImpl] respaldado por Supabase. En
/// pruebas puede sobrescribirse con un doble mediante
/// `authRepositoryProvider.overrideWithValue(...)`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(),
);

/// Flujo de los cambios de estado de autenticación (Req 7.3).
///
/// Reexpone `AuthRepository.authStateChanges()` como `StreamProvider` para que
/// la guarda de enrutado y otras partes de la UI puedan reaccionar a los
/// inicios/cierres de sesión y a los eventos de recuperación de contraseña.
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// `AsyncNotifier` que orquesta las operaciones de autenticación.
///
/// El estado es `AsyncValue<AppUser?>`:
///   - `AsyncData(null)`: no hay operación en curso ni usuario autenticado por
///     esta sesión del notifier (estado inicial / tras cerrar sesión).
///   - `AsyncData(AppUser)`: la última operación con éxito devolvió el perfil
///     del Usuario (registro o inicio de sesión).
///   - `AsyncLoading`: hay una operación en curso (muestra el indicador).
///   - `AsyncError`: la última operación falló; el error suele ser un `Failure`
///     con un mensaje en español listo para mostrar.
///
/// La fuente de verdad de la sesión sigue siendo Supabase (observada mediante
/// [authStateChangesProvider] por la guarda de enrutado); este notifier solo
/// orquesta los comandos y expone sus estados de carga/éxito/error.
class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    // Estado inicial: sin operación en curso ni resultado previo.
    return null;
  }

  /// Registra un nuevo Usuario y expone el perfil resultante (Req 1.1, 1.7).
  ///
  /// Durante la operación el estado pasa a `AsyncLoading` y, al terminar, a
  /// `AsyncData` con el perfil creado o `AsyncError` si falla (p. ej. email en
  /// uso o contraseña demasiado corta).
  ///
  /// Devuelve el resultado del alta como [SignUpResult]: `sesionIniciada`
  /// cuando el registro deja sesión activa (el enrutado navega solo) o
  /// `confirmacionPendiente` cuando Auth requiere confirmar el correo (la UI
  /// debe avisar y volver al login). Si la operación falla, se relanza el error.
  Future<SignUpResult> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
    XFile? foto,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard(
      () => repository.signUp(
        nombre: nombre,
        apellidos: apellidos,
        email: email,
        password: password,
        foto: foto,
      ),
    );

    // Si falló, se relanza para que la pantalla muestre el error.
    if (state.hasError) {
      // ignore: only_throw_errors
      throw state.error!;
    }

    // `AsyncData(null)` tras un alta correcta significa que no hay sesión aún:
    // el registro quedó pendiente de confirmación por correo.
    return state.value == null
        ? SignUpResult.confirmacionPendiente
        : SignUpResult.sesionIniciada;
  }

  /// Inicia sesión con [email] y [password] (Req 2.1).
  ///
  /// Al tener éxito, Supabase emite el cambio de sesión que la guarda de
  /// enrutado observa para pasar a la zona autenticada. El estado refleja la
  /// carga y los errores (credenciales inválidas / cuenta suspendida).
  Future<void> signIn({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard(
      () => repository.signIn(email: email, password: password),
    );
  }

  /// Cierra la sesión activa del Usuario (Req 2.4).
  ///
  /// Al terminar deja el estado en `AsyncData(null)`; la guarda de enrutado
  /// reacciona al cambio de sesión de Supabase para volver a la zona pública.
  Future<void> signOut() async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard(() async {
      await repository.signOut();
      return null;
    });
  }

  /// Solicita el restablecimiento de la contraseña asociada a [email] (Req 9.1).
  ///
  /// La operación siempre se considera exitosa de cara a la UI (no revela si el
  /// email existe); el estado queda en `AsyncData(null)` tras completarse para
  /// que la pantalla muestre el mensaje genérico.
  Future<void> requestPasswordReset(String email) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard(() async {
      await repository.requestPasswordReset(email);
      return null;
    });
  }

  /// Fija la nueva contraseña dentro de la sesión de recuperación (Req 9.6/9.7).
  ///
  /// Durante la operación el estado pasa a `AsyncLoading` y, al terminar, a
  /// `AsyncData(null)` en caso de éxito o `AsyncError` si falla (contraseña
  /// demasiado corta, token inválido/caducado o cuenta suspendida).
  Future<void> updatePasswordWithToken(String newPassword) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncValue<AppUser?>.loading();
    state = await AsyncValue.guard(() async {
      await repository.updatePasswordWithToken(newPassword);
      return null;
    });
  }
}

/// Expone el estado de las operaciones de autenticación (carga/éxito/error).
final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
