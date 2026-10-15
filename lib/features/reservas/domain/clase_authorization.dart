// Guarda de autorización pura (en memoria) del CRUD de Clases del
// Servicio_Reservas.
//
// Replica, como lógica de dominio pura y sin dependencia de Supabase, la
// comprobación de rol que las políticas RLS de PostgreSQL (migración 0003)
// realizan sobre la tabla `clases`: INSERT/UPDATE/DELETE solo se permiten si
// `es_superadmin()` (ver design.md, "Security and RLS Strategy", y la capa de
// datos `ReservasRepositoryImpl`, que traduce el rechazo por RLS/sin sesión al
// [AutorizacionInsuficienteFailure]).
//
// Invariante modelada (Req 8.2):
// - Toda operación de modificación de Clases (crear, editar, eliminar) solo se
//   permite al llamante con rol 'superadmin'.
// - Si el llamante tiene rol estándar ('usuario'), la operación se deniega con
//   [AutorizacionInsuficienteFailure] y un mensaje de autorización
//   insuficiente, sin modificar la Clase.

import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Operaciones de modificación de Clases sujetas a la comprobación de rol de
/// superadministrador en el backend (Req 8.2).
enum OperacionClase {
  /// Crear una nueva Clase (`INSERT` sobre `clases`).
  crear,

  /// Editar una Clase existente (`UPDATE` sobre `clases`).
  editar,

  /// Eliminar una Clase (`DELETE` sobre `clases`).
  eliminar,
}

/// Verifica si [rolLlamante] está autorizado a modificar Clases.
///
/// Espeja la comprobación `es_superadmin()` del backend: solo el rol
/// 'superadmin' puede crear, editar o eliminar Clases (Req 8.2).
bool estaAutorizadoParaModificarClases(RolUsuario rolLlamante) =>
    rolLlamante == RolUsuario.superadmin;

/// Autoriza (o deniega) una [operacion] de modificación de Clases según el
/// [rolLlamante].
///
/// Devuelve `null` cuando el llamante es superadministrador (acceso permitido),
/// o un [AutorizacionInsuficienteFailure] cuando el llamante tiene rol estándar
/// (acceso denegado con mensaje de autorización insuficiente, Req 8.2).
///
/// El parámetro [operacion] se acepta para dejar explícito que la guarda es
/// uniforme para *cualquier* operación de modificación de Clases: crear, editar
/// y eliminar comparten la misma regla de autorización.
AutorizacionInsuficienteFailure? autorizarModificacionClase(
  RolUsuario rolLlamante,
  OperacionClase operacion,
) {
  if (estaAutorizadoParaModificarClases(rolLlamante)) {
    return null;
  }
  return const AutorizacionInsuficienteFailure();
}
