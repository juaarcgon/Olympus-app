// Providers de Riverpod para el Servicio_Usuarios (perfil propio).
//
// Esta capa de estado (Application) orquesta el caso de uso de perfil sobre el
// [ProfileRepository] de dominio y expone estados inmutables de carga/éxito/
// error que la UI observa:
//
//   - [profileRepositoryProvider]: inyecta la implementación concreta del
//     repositorio ([ProfileRepositoryImpl]) de forma testable (se puede
//     sobrescribir en pruebas con `overrideWithValue`).
//   - [ProfileNotifier] / [profileNotifierProvider]: `AsyncNotifier` que carga
//     el perfil del Usuario autenticado al construirse (Req 3.1) y expone
//     `updateProfile(...)` para actualizar nombre, apellidos y/o foto (Req 3.2)
//     reflejando los estados de carga y error.
//
// No se exponen operaciones para modificar `saldo_clases` ni `estado`: el
// repositorio de dominio tampoco lo permite (Req 3.3, 3.4), y la RLS lo
// refuerza en el backend.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';

/// Provee la implementación del [ProfileRepository] (Servicio_Usuarios).
///
/// Por defecto construye un [ProfileRepositoryImpl] respaldado por Supabase.
/// En pruebas puede sobrescribirse con un doble mediante
/// `profileRepositoryProvider.overrideWithValue(...)`.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepositoryImpl(),
);

/// `AsyncNotifier` que gestiona el estado del perfil del Usuario autenticado.
///
/// Al construirse carga el perfil propio con [ProfileRepository.getMyProfile]
/// (Req 3.1); el estado resultante es `AsyncData<Profile>` en caso de éxito,
/// `AsyncLoading` mientras carga y `AsyncError` si falla (p. ej. sin sesión).
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() {
    // Carga inicial del perfil propio (Req 3.1).
    return ref.read(profileRepositoryProvider).getMyProfile();
  }

  /// Actualiza los campos editables del perfil y refresca el estado (Req 3.2).
  ///
  /// Solo se envían los parámetros no nulos; los omitidos conservan su valor
  /// actual. Durante la operación el estado pasa a `AsyncLoading` y, al
  /// terminar, a `AsyncData` con el perfil actualizado o `AsyncError` si falla.
  /// Nunca modifica `saldo_clases` ni `estado` (Req 3.3, 3.4).
  Future<void> updateProfile({
    String? nombre,
    String? apellidos,
    XFile? foto,
  }) async {
    final repository = ref.read(profileRepositoryProvider);
    // Indica el estado de carga durante la actualización (Req 3.2).
    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => repository.updateMyProfile(
        nombre: nombre,
        apellidos: apellidos,
        foto: foto,
      ),
    );
  }

  /// Vuelve a cargar el perfil propio desde el backend (Req 3.1).
  Future<void> refresh() async {
    state = const AsyncValue<Profile>.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getMyProfile(),
    );
  }
}

/// Expone el estado del perfil del Usuario autenticado (carga/éxito/error).
final profileNotifierProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);
