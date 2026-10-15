// Modelo puro (en memoria) de la eliminación de usuarios por un
// superadministrador para la app Olympus.
//
// Replica la lógica de la función RPC del backend `eliminar_usuario`
// (ver design.md, "Funciones RPC del backend", y `0005_rpc_admin.sql`) como un
// modelo de dominio puro, inmutable y sin dependencia de Supabase. La capa de
// datos `AdminRepositoryImpl` traduce el error de autoeliminación del backend
// (`42501` con mensaje de autoeliminación) a [AutoeliminacionFailure]; aquí se
// modela esa misma regla de negocio para poder verificarla con pruebas de
// propiedad rápidas y deterministas.
//
// Invariante modelada (Req 6.7):
// - Un superadministrador no puede eliminar su propia cuenta: el intento se
//   rechaza con [AutoeliminacionFailure] y la cuenta persiste inalterada.
//
// Para contrastar la regla, el modelo también refleja el resto del
// comportamiento relevante de la RPC: la eliminación de *otro* usuario por un
// superadministrador tiene éxito y borra su registro (Req 6.4), y un llamante
// sin rol de superadministrador es denegado por autorización (Req 5.4).

import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Estado inmutable en memoria del conjunto de usuarios y sus roles.
///
/// Modela lo necesario para la invariante de autoeliminación: el rol de cada
/// usuario indexado por su id. Es la fuente de verdad sobre la que opera
/// [eliminarUsuario], que devuelve siempre un nuevo estado sin mutar el actual.
class EliminacionEstado {
  /// Crea un estado a partir del mapa de roles por id de usuario.
  ///
  /// Copia defensivamente el mapa recibido para garantizar la inmutabilidad.
  EliminacionEstado(Map<String, RolUsuario> roles)
    : roles = Map<String, RolUsuario>.unmodifiable(roles);

  /// Rol de cada Usuario, indexado por su id. La presencia de la clave indica
  /// que la cuenta existe; su ausencia, que la cuenta ha sido eliminada.
  final Map<String, RolUsuario> roles;

  /// Indica si la cuenta [userId] existe en el estado actual.
  bool existe(String userId) => roles.containsKey(userId);

  /// Rol de [userId], o `null` si la cuenta no existe.
  RolUsuario? rolDe(String userId) => roles[userId];

  /// Elimina la cuenta [targetUserId] a petición de [callerId] (replica
  /// `eliminar_usuario`).
  ///
  /// Reglas, en el mismo orden que la RPC del backend:
  /// 1. Autorización (Req 5.4): si [callerId] no es superadministrador, se
  ///    rechaza con [AutorizacionInsuficienteFailure] sin modificar el estado.
  /// 2. Autoeliminación (Req 6.7): si [targetUserId] es el propio [callerId],
  ///    se rechaza con [AutoeliminacionFailure] y la cuenta persiste.
  /// 3. Dato no encontrado: si la cuenta objetivo no existe, se rechaza con
  ///    [OperacionFallidaFailure] sin modificar el estado.
  /// 4. En otro caso: elimina la cuenta objetivo y devuelve el nuevo estado.
  ///
  /// Devuelve un [EliminacionResult] con el estado resultante y el desenlace.
  EliminacionResult eliminarUsuario({
    required String callerId,
    required String targetUserId,
  }) {
    // 1. Autorización: solo un superadministrador puede eliminar (Req 5.4).
    if (roles[callerId] != RolUsuario.superadmin) {
      return EliminacionResult.fallo(
        this,
        const AutorizacionInsuficienteFailure(),
      );
    }

    // 2. Autoeliminación: un superadministrador no puede eliminarse a sí mismo
    //    (Req 6.7). La cuenta persiste inalterada.
    if (targetUserId == callerId) {
      return EliminacionResult.fallo(this, const AutoeliminacionFailure());
    }

    // 3. Dato no encontrado: la cuenta objetivo debe existir (Req 6.4).
    if (!existe(targetUserId)) {
      return EliminacionResult.fallo(this, const OperacionFallidaFailure());
    }

    // 4. Elimina el registro del usuario objetivo (Req 6.4).
    final nuevosRoles = Map<String, RolUsuario>.from(roles)
      ..remove(targetUserId);
    return EliminacionResult.exito(EliminacionEstado(nuevosRoles));
  }

  @override
  String toString() => 'EliminacionEstado(roles: $roles)';
}

/// Resultado de [EliminacionEstado.eliminarUsuario].
///
/// Contiene el [estado] resultante (siempre no nulo; coincide con el estado
/// previo cuando la operación se rechaza) y, de forma mutuamente excluyente, el
/// [failure] en caso de rechazo.
class EliminacionResult {
  const EliminacionResult._({required this.estado, this.failure});

  /// Crea un resultado de eliminación exitosa.
  const EliminacionResult.exito(EliminacionEstado estado)
    : this._(estado: estado);

  /// Crea un resultado de eliminación rechazada; el estado no cambia.
  const EliminacionResult.fallo(EliminacionEstado estado, Failure failure)
    : this._(estado: estado, failure: failure);

  /// Estado resultante de la operación.
  final EliminacionEstado estado;

  /// Fallo de dominio cuando la eliminación fue rechazada; `null` si tuvo éxito.
  final Failure? failure;

  /// Indica si la operación tuvo éxito.
  bool get esExito => failure == null;

  @override
  String toString() => esExito
      ? 'EliminacionResult.exito($estado)'
      : 'EliminacionResult.fallo($failure)';
}
