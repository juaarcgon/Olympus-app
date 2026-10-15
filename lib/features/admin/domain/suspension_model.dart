// Modelo puro (en memoria) de la suspensión y reactivación de usuarios por un
// superadministrador para la app Olympus.
//
// Replica la lógica de las funciones RPC del backend `suspender_usuario` y
// `reactivar_usuario` (ver design.md, "Funciones RPC del backend", y
// `0005_rpc_admin.sql`) como un modelo de dominio puro, inmutable y sin
// dependencia de Supabase. La capa de datos `AdminRepositoryImpl` invoca esas
// RPC desde `suspendUser`/`reactivateUser`; aquí se modela esa misma regla de
// negocio para poder verificarla con pruebas de propiedad rápidas y
// deterministas.
//
// Invariantes modeladas (Req 6.2, 6.3):
// - Suspender a un Usuario fija su `estado` en 'suspendido' (Req 6.2).
// - Reactivar a un Usuario fija su `estado` en 'activo' (Req 6.3).
// - Ambas operaciones son deterministas e idempotentes respecto al estado
//   objetivo: suspender dos veces deja 'suspendido'; reactivar dos veces deja
//   'activo'. El round trip suspender→reactivar restaura 'activo' partiendo de
//   cualquier estado inicial.

import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Estado inmutable en memoria del `estado` (activo/suspendido) de un conjunto
/// de usuarios, indexado por su id.
///
/// Modela únicamente lo necesario para las transiciones de suspensión y
/// reactivación. Es la fuente de verdad sobre la que operan [suspender] y
/// [reactivar], que devuelven siempre un nuevo estado sin mutar el actual.
class SuspensionEstado {
  /// Crea un estado a partir del mapa de estados por id de usuario.
  ///
  /// Copia defensivamente el mapa recibido para garantizar la inmutabilidad.
  SuspensionEstado(Map<String, EstadoUsuario> estados)
    : estados = Map<String, EstadoUsuario>.unmodifiable(estados);

  /// Estado de cada Usuario (activo/suspendido), indexado por su id.
  final Map<String, EstadoUsuario> estados;

  /// Indica si la cuenta [userId] existe en el estado actual.
  bool existe(String userId) => estados.containsKey(userId);

  /// Estado de [userId], o `null` si la cuenta no existe.
  EstadoUsuario? estadoDe(String userId) => estados[userId];

  /// Da de baja al Usuario [userId] (replica `suspender_usuario`).
  ///
  /// Fija su `estado` en 'suspendido' (Req 6.2) de forma determinista, con
  /// independencia del estado previo. Devuelve un nuevo [SuspensionEstado]; el
  /// resto de cuentas permanece inalterado.
  SuspensionEstado suspender(String userId) =>
      _conEstado(userId, EstadoUsuario.suspendido);

  /// Reactiva al Usuario [userId] (replica `reactivar_usuario`).
  ///
  /// Fija su `estado` en 'activo' (Req 6.3) de forma determinista, con
  /// independencia del estado previo. Devuelve un nuevo [SuspensionEstado]; el
  /// resto de cuentas permanece inalterado.
  SuspensionEstado reactivar(String userId) =>
      _conEstado(userId, EstadoUsuario.activo);

  /// Devuelve un nuevo estado con [userId] fijado en [nuevoEstado].
  SuspensionEstado _conEstado(String userId, EstadoUsuario nuevoEstado) {
    final nuevosEstados = <String, EstadoUsuario>{
      ...estados,
      userId: nuevoEstado,
    };
    return SuspensionEstado(nuevosEstados);
  }

  @override
  String toString() => 'SuspensionEstado(estados: $estados)';
}
