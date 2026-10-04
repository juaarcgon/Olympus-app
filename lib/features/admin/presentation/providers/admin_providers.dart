// Providers de Riverpod para el Servicio_Administracion (panel de superadmin).
//
// Esta capa de estado (Application) orquesta el caso de uso de gestión de
// Usuarios sobre el [AdminRepository] de dominio y expone estados inmutables
// de carga/éxito/error que la UI del panel de administración observa:
//
//   - [adminRepositoryProvider]: inyecta la implementación concreta del
//     repositorio ([AdminRepositoryImpl]) de forma testable (se puede
//     sobrescribir en pruebas con `overrideWithValue`).
//   - [AdminNotifier] / [adminNotifierProvider]: `AsyncNotifier` que carga la
//     lista de Usuarios al construirse (Req 6.1) y expone las operaciones
//     administrativas (suspender, reactivar, eliminar, restablecer/ajustar
//     bono, conceder superadmin) que invocan el repositorio y refrescan la
//     lista, propagando los `Failure` de dominio tipados.
//
// Mantiene el mismo estilo que `profile_providers.dart`: `AsyncNotifier` que
// construye su estado inicial en `build()` y usa `AsyncValue.guard` para
// reflejar los estados de carga/error en las operaciones.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/domain/entities/profile.dart';
import '../../data/repositories/admin_repository_impl.dart';
import '../../domain/repositories/admin_repository.dart';

/// Provee la implementación del [AdminRepository] (Servicio_Administracion).
///
/// Por defecto construye un [AdminRepositoryImpl] respaldado por Supabase.
/// En pruebas puede sobrescribirse con un doble mediante
/// `adminRepositoryProvider.overrideWithValue(...)`.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepositoryImpl(),
);

/// `AsyncNotifier` que gestiona el estado de la lista de Usuarios del panel de
/// administración.
///
/// Al construirse carga todos los Usuarios con [AdminRepository.listUsers]
/// (Req 6.1); el estado resultante es `AsyncData<List<Profile>>` en caso de
/// éxito, `AsyncLoading` mientras carga y `AsyncError` si falla (p. ej. sin
/// autorización).
class AdminNotifier extends AsyncNotifier<List<Profile>> {
  @override
  Future<List<Profile>> build() {
    // Carga inicial del listado de Usuarios (Req 6.1).
    return ref.read(adminRepositoryProvider).listUsers();
  }

  /// Vuelve a cargar la lista de Usuarios desde el backend (Req 6.1).
  Future<void> refresh() async {
    state = const AsyncValue<List<Profile>>.loading();
    state = await AsyncValue.guard(
      () => ref.read(adminRepositoryProvider).listUsers(),
    );
  }

  /// Da de baja a un Usuario (Req 6.2) y refresca la lista.
  ///
  /// Propaga cualquier `Failure` de dominio (p. ej.
  /// [AutorizacionInsuficienteFailure]) para que la UI lo muestre; en ese caso
  /// la lista no se altera.
  Future<void> suspend(String userId) =>
      _ejecutarYRefrescar((repo) => repo.suspendUser(userId));

  /// Reactiva a un Usuario suspendido (Req 6.3) y refresca la lista.
  Future<void> reactivate(String userId) =>
      _ejecutarYRefrescar((repo) => repo.reactivateUser(userId));

  /// Elimina el registro de un Usuario (Req 6.4) y refresca la lista.
  ///
  /// Propaga [AutoeliminacionFailure] si un superadministrador intenta
  /// eliminarse a sí mismo (Req 6.7).
  Future<void> delete(String userId) =>
      _ejecutarYRefrescar((repo) => repo.deleteUser(userId));

  /// Restablece el bono de un Usuario a 10 (Req 6.5) y refresca la lista.
  Future<void> restablecerBono(String userId) =>
      _ejecutarYRefrescar((repo) => repo.restablecerBono(userId));

  /// Ajusta el saldo de clases de un Usuario al [valor] indicado (Req 6.6) y
  /// refresca la lista.
  ///
  /// Propaga [BonoFueraDeRangoFailure] si [valor] está fuera de 0..10.
  Future<void> ajustarBono(String userId, int valor) =>
      _ejecutarYRefrescar((repo) => repo.ajustarBono(userId, valor));

  /// Concede el rol de superadministrador a un Usuario (Req 5.1, 5.2) y
  /// refresca la lista.
  ///
  /// Propaga [MaxSuperadminsFailure] si ya existen dos superadministradores.
  Future<void> grantSuperadmin(String userId) =>
      _ejecutarYRefrescar((repo) => repo.grantSuperadmin(userId));

  /// Ejecuta una operación administrativa sobre el repositorio y, si tiene
  /// éxito, recarga el listado para reflejar el nuevo estado (Req 6.1).
  ///
  /// Si la operación lanza un `Failure`, se vuelve a lanzar para que la UI lo
  /// capture y lo muestre como mensaje en español; el estado de la lista no se
  /// deja en `AsyncError` por un fallo de una acción puntual.
  Future<void> _ejecutarYRefrescar(
    Future<void> Function(AdminRepository repo) accion,
  ) async {
    final repository = ref.read(adminRepositoryProvider);
    await accion(repository);
    await refresh();
  }
}

/// Expone el estado de la lista de Usuarios del panel de administración.
final adminNotifierProvider =
    AsyncNotifierProvider<AdminNotifier, List<Profile>>(AdminNotifier.new);
