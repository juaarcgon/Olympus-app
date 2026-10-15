// Modelo de control de acceso a datos de usuario (en memoria, puro).
//
// Replica, como lógica de dominio pura y sin dependencia de Supabase, la
// política RLS de SELECT sobre los datos de usuario de la tabla `profiles`
// (ver design.md, "Security and RLS Strategy", y las migraciones
// `0003_rls.sql`). La política del backend es, en esencia:
//
//   USING (auth.uid() = id OR es_superadmin())
//
// y, de forma crucial, no existe ninguna política para el rol `anon`: una
// petición sin JWT (sin Sesion activa) no satisface ninguna política y, por
// tanto, no devuelve ninguna fila (Req 7.3).
//
// Este modelo espeja esa semántica mediante una función pura que decide, para
// una petición de datos de usuario, cuántas filas devuelve el backend:
//   - Sin Sesion activa (solicitante nulo): 0 filas, acceso denegado (Req 7.3).
//   - Con Sesion activa: 1 fila si el solicitante accede a sus propios datos o
//     es superadministrador; 0 filas en caso contrario (Req 7.2).
//
// Se comparte entre las pruebas de propiedad de seguridad (Property 19 y
// Property 20). La aplicación real de RLS se verifica, además, con las pruebas
// de integración contra una instancia de Supabase.

import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Identidad del solicitante de una petición de datos de usuario.
///
/// Modela el `auth.uid()` y el rol efectivo del llamante autenticado. La
/// ausencia de identidad (ningún [Solicitante], es decir `null`) representa una
/// petición sin Sesion activa (rol `anon`, sin JWT).
class Solicitante {
  const Solicitante({required this.id, required this.rol});

  /// Identificador del Usuario autenticado (equivalente a `auth.uid()`).
  final String id;

  /// Rol efectivo del Usuario autenticado.
  final RolUsuario rol;

  /// Indica si el solicitante tiene rol de superadministrador.
  bool get esSuperadmin => rol == RolUsuario.superadmin;

  @override
  String toString() => 'Solicitante(id: $id, rol: ${rol.valor})';
}

/// Petición de lectura de los datos del Usuario con id [objetivoId], realizada
/// por [solicitante].
///
/// Un [solicitante] `null` representa la ausencia de Sesion activa (petición
/// anónima, sin JWT).
class PeticionDatosUsuario {
  const PeticionDatosUsuario({
    required this.solicitante,
    required this.objetivoId,
  });

  /// Identidad autenticada del solicitante, o `null` si no hay Sesion activa.
  final Solicitante? solicitante;

  /// Identificador del Usuario cuyos datos se solicitan.
  final String objetivoId;

  /// Indica si la petición se realiza sin una Sesion activa (rol `anon`).
  bool get sinSesion => solicitante == null;

  @override
  String toString() =>
      'PeticionDatosUsuario(solicitante: $solicitante, '
      'objetivoId: $objetivoId)';
}

/// Número de filas que el backend devuelve para una [peticion] de datos de
/// usuario, según la política RLS de SELECT sobre `profiles`.
///
/// Espeja `USING (auth.uid() = id OR es_superadmin())` y la ausencia de
/// política para `anon`:
///   - Sin Sesion activa: 0 filas (Req 7.3).
///   - Con Sesion activa: 1 fila si accede a sus propios datos o es
///     superadministrador; 0 filas en otro caso (Req 7.2).
int filasVisiblesPara(PeticionDatosUsuario peticion) {
  final solicitante = peticion.solicitante;
  // Sin Sesion activa (rol `anon`, sin JWT): ninguna política aplica, por lo
  // que no se devuelve ninguna fila (Req 7.3).
  if (solicitante == null) {
    return 0;
  }
  // Con Sesion activa: solo los propios datos o acceso de superadministrador
  // (Req 7.2).
  if (solicitante.id == peticion.objetivoId || solicitante.esSuperadmin) {
    return 1;
  }
  return 0;
}

/// Indica si una [peticion] de datos de usuario tiene acceso concedido, es
/// decir, si el backend devolvería al menos una fila.
bool accesoConcedido(PeticionDatosUsuario peticion) =>
    filasVisiblesPara(peticion) > 0;
