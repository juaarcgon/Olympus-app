// Modelo puro (en memoria) de concesión del rol de superadministrador para la
// app Olympus.
//
// Replica la lógica de la función RPC del backend `conceder_superadmin`
// (ver design.md, "Funciones RPC del backend" y "invariante de máximo 2
// superadmins") como un modelo de dominio puro, inmutable y sin dependencia de
// Supabase. Esto permite verificar la invariante de "como máximo dos
// superadministradores" mediante pruebas de propiedad rápidas y deterministas.
//
// Invariante modelada (Req 5.1, 5.2):
// - El número de usuarios con rol 'superadmin' nunca supera dos (2).
// - Todo intento de conceder el rol cuando ya existen dos (2) superadmins se
//   rechaza con [MaxSuperadminsFailure], dejando el estado inalterado.
// - Conceder el rol a un usuario que ya es superadmin es idempotente: no cambia
//   el estado ni cuenta como una nueva concesión (espejo del `return` temprano
//   de la RPC cuando el rol objetivo ya es 'superadmin').

import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Número máximo de superadministradores admitido por el Sistema (Req 5.1).
const int kMaxSuperadmins = 2;

/// Estado inmutable en memoria del conjunto de usuarios y sus roles.
///
/// Modela únicamente lo necesario para la invariante de superadmins: el rol de
/// cada usuario indexado por su id. Es la fuente de verdad sobre la que opera
/// [concederSuperadmin], que devuelve siempre un nuevo estado sin mutar el
/// actual.
class SuperadminEstado {
  /// Crea un estado a partir del mapa de roles por id de usuario.
  ///
  /// Copia defensivamente el mapa recibido para garantizar la inmutabilidad.
  SuperadminEstado(Map<String, RolUsuario> roles)
    : roles = Map<String, RolUsuario>.unmodifiable(roles);

  /// Rol de cada Usuario, indexado por su id.
  final Map<String, RolUsuario> roles;

  /// Número de usuarios con rol 'superadmin' en el estado actual.
  int get totalSuperadmins =>
      roles.values.where((rol) => rol == RolUsuario.superadmin).length;

  /// Indica si [userId] tiene rol de superadministrador.
  bool esSuperadmin(String userId) => roles[userId] == RolUsuario.superadmin;

  /// Concede el rol de superadministrador a [userId] (replica
  /// `conceder_superadmin`).
  ///
  /// Reglas (Req 5.1, 5.2):
  /// - Si [userId] ya es superadmin: operación idempotente, devuelve el mismo
  ///   estado como éxito sin alterar el conteo.
  /// - Si ya existen dos (2) superadmins: se rechaza con
  ///   [MaxSuperadminsFailure] sin modificar el estado.
  /// - En otro caso: asigna el rol 'superadmin' a [userId] y devuelve el nuevo
  ///   estado.
  ///
  /// Devuelve un [ConcederResult] con el nuevo estado y el desenlace o fallo.
  ConcederResult concederSuperadmin(String userId) {
    // Idempotencia: si ya es superadmin, no cuenta como nueva concesión.
    if (esSuperadmin(userId)) {
      return ConcederResult.exito(this);
    }

    // Invariante: máximo dos (2) superadministradores (Req 5.1, 5.2).
    if (totalSuperadmins >= kMaxSuperadmins) {
      return ConcederResult.fallo(this, const MaxSuperadminsFailure());
    }

    // Asigna el rol de superadministrador al usuario objetivo.
    final nuevosRoles = <String, RolUsuario>{
      ...roles,
      userId: RolUsuario.superadmin,
    };
    return ConcederResult.exito(SuperadminEstado(nuevosRoles));
  }

  @override
  String toString() =>
      'SuperadminEstado(totalSuperadmins: $totalSuperadmins, roles: $roles)';
}

/// Resultado de [SuperadminEstado.concederSuperadmin].
///
/// Contiene el nuevo [estado] (siempre no nulo; coincide con el estado previo
/// cuando la operación se rechaza) y, de forma mutuamente excluyente, el
/// [failure] en caso de rechazo.
class ConcederResult {
  const ConcederResult._({required this.estado, this.failure});

  /// Crea un resultado de concesión exitosa (o idempotente).
  const ConcederResult.exito(SuperadminEstado estado) : this._(estado: estado);

  /// Crea un resultado de concesión rechazada; el estado no cambia.
  const ConcederResult.fallo(SuperadminEstado estado, Failure failure)
    : this._(estado: estado, failure: failure);

  /// Estado resultante de la operación.
  final SuperadminEstado estado;

  /// Fallo de dominio cuando la concesión fue rechazada; `null` si tuvo éxito.
  final Failure? failure;

  /// Indica si la operación tuvo éxito.
  bool get esExito => failure == null;

  @override
  String toString() => esExito
      ? 'ConcederResult.exito($estado)'
      : 'ConcederResult.fallo($failure)';
}
