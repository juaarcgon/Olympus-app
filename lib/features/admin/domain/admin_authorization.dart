// Guarda de autorización pura (en memoria) del Servicio_Administracion.
//
// Replica, como lógica de dominio pura y sin dependencia de Supabase, la
// comprobación de rol que las funciones RPC `SECURITY DEFINER` del backend
// realizan mediante `es_superadmin()` antes de ejecutar cualquier operación de
// gestión de usuarios (ver design.md, "Funciones RPC del backend", y la capa
// de datos `AdminRepositoryImpl`, que traduce el `42501` del backend a
// [AutorizacionInsuficienteFailure]).
//
// Invariante modelada (Req 5.4):
// - Toda operación de gestión de usuarios (suspender, reactivar, eliminar,
//   restablecer/ajustar bono, conceder superadmin) solo se permite al llamante
//   con rol 'superadmin'.
// - Si el llamante tiene rol estándar ('usuario'), la operación se deniega con
//   [AutorizacionInsuficienteFailure] y un mensaje de autorización
//   insuficiente, sin ejecutar efecto alguno.

import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Operaciones de gestión de usuarios sujetas a la comprobación de rol de
/// superadministrador en el backend (Req 5.4, 6.2–6.7, 5.1).
enum OperacionGestion {
  /// Dar de baja a un usuario (`suspend_user`).
  suspender,

  /// Reactivar a un usuario suspendido (`reactivate_user`).
  reactivar,

  /// Eliminar el registro de un usuario (`delete_user`).
  eliminar,

  /// Restablecer el bono a 10 clases (`restablecer_bono`).
  restablecerBono,

  /// Ajustar el saldo del bono (`ajustar_bono`).
  ajustarBono,

  /// Conceder el rol de superadministrador (`conceder_superadmin`).
  concederSuperadmin,
}

/// Verifica si [rolLlamante] está autorizado a ejecutar una
/// [OperacionGestion].
///
/// Espeja la comprobación `es_superadmin()` del backend: solo el rol
/// 'superadmin' puede ejecutar operaciones de gestión de usuarios (Req 5.4).
bool estaAutorizadoParaGestion(RolUsuario rolLlamante) =>
    rolLlamante == RolUsuario.superadmin;

/// Autoriza (o deniega) una [operacion] de gestión según el [rolLlamante].
///
/// Devuelve `null` cuando el llamante es superadministrador (acceso permitido),
/// o un [AutorizacionInsuficienteFailure] cuando el llamante tiene rol estándar
/// (acceso denegado con mensaje de autorización insuficiente, Req 5.4).
///
/// El parámetro [operacion] se acepta para dejar explícito que la guarda es
/// uniforme para *cualquier* operación de gestión: todas comparten la misma
/// regla de autorización.
AutorizacionInsuficienteFailure? autorizarGestion(
  RolUsuario rolLlamante,
  OperacionGestion operacion,
) {
  if (estaAutorizadoParaGestion(rolLlamante)) {
    return null;
  }
  return const AutorizacionInsuficienteFailure();
}
