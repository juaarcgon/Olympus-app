// Guarda de acceso pura (en memoria) del Servicio_Usuarios.
//
// Replica, como lógica de dominio pura y sin dependencia de Supabase, la
// decisión de la política RLS `SELECT` sobre la tabla `profiles` del backend
// (ver design.md, "Security and RLS Strategy"):
//
//     profiles SELECT USING (auth.uid() = id OR es_superadmin())
//
// Es decir: una petición de los datos de un Usuario (objetivo) solo se concede
// si el solicitante es ese mismo Usuario o si tiene rol de superadministrador.
// En cualquier otro caso la petición se deniega con
// [AutorizacionInsuficienteFailure] y un mensaje de autorización insuficiente
// (Req 7.2). La enforcement real en producción la hace PostgreSQL vía RLS; esta
// función es su espejo verificable con pruebas de dominio puro.

import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Decide si el solicitante puede acceder a los datos del usuario objetivo.
///
/// Espeja la condición RLS `auth.uid() = id OR es_superadmin()`:
/// - El solicitante accede a sus propios datos (`solicitanteId == objetivoId`).
/// - Un superadministrador accede a los datos de cualquier usuario.
///
/// Devuelve `true` cuando el acceso está permitido y `false` en caso contrario.
bool puedeAccederAProfile({
  required String solicitanteId,
  required RolUsuario solicitanteRol,
  required String objetivoId,
}) {
  final esElPropio = solicitanteId == objetivoId;
  final esSuperadmin = solicitanteRol == RolUsuario.superadmin;
  return esElPropio || esSuperadmin;
}

/// Autoriza (o deniega) la petición de los datos del usuario [objetivoId] por
/// parte del solicitante identificado por [solicitanteId] con rol
/// [solicitanteRol].
///
/// Devuelve `null` cuando el acceso está permitido (es el propio usuario o un
/// superadministrador), o un [AutorizacionInsuficienteFailure] con un mensaje
/// de autorización insuficiente cuando la petición debe denegarse (Req 7.2).
AutorizacionInsuficienteFailure? autorizarAccesoAProfile({
  required String solicitanteId,
  required RolUsuario solicitanteRol,
  required String objetivoId,
}) {
  if (puedeAccederAProfile(
    solicitanteId: solicitanteId,
    solicitanteRol: solicitanteRol,
    objetivoId: objetivoId,
  )) {
    return null;
  }
  return const AutorizacionInsuficienteFailure();
}
