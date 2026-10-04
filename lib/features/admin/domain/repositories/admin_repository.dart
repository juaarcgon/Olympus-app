// Contrato de dominio del Servicio_Administracion (AdminRepository).
//
// Define las operaciones de gestión de Usuarios disponibles para un
// Superadministrador con Sesion activa. Todas estas operaciones se materializan
// en el backend como funciones RPC `SECURITY DEFINER` que validan el rol de
// superadministrador (`es_superadmin()`), de modo que la autorización crítica
// ocurre en PostgreSQL aunque el cliente la omita (Req 5.3, 5.4).
//
// La interfaz es independiente del SDK de Supabase para facilitar las pruebas y
// futuras sustituciones; la implementación concreta vive en la capa de datos y
// traduce las excepciones del backend a `Failure` de dominio tipados.

import '../../../profile/domain/entities/profile.dart';

/// Servicio_Administracion: gestión de Usuarios y superadministradores.
abstract class AdminRepository {
  /// Devuelve la lista de Usuarios con su nombre, apellidos, correo
  /// electrónico, Estado_Usuario y Saldo_De_Clases (Req 6.1).
  ///
  /// La política RLS de `SELECT` sobre `profiles` solo devuelve todas las filas
  /// cuando el llamante es superadministrador; en caso contrario la lista queda
  /// restringida a su propia fila.
  Future<List<Profile>> listUsers();

  /// Da de baja a un Usuario fijando su Estado_Usuario en `'suspendido'`
  /// (Req 6.2). Lanza [AutorizacionInsuficienteFailure] si el llamante no es
  /// superadministrador (Req 5.4).
  Future<void> suspendUser(String userId);

  /// Reactiva a un Usuario suspendido fijando su Estado_Usuario en `'activo'`
  /// (Req 6.3). Lanza [AutorizacionInsuficienteFailure] si no está autorizado.
  Future<void> reactivateUser(String userId);

  /// Elimina el registro de un Usuario de la base de datos (Req 6.4).
  ///
  /// Lanza [AutoeliminacionFailure] si un superadministrador intenta eliminar
  /// su propia cuenta (Req 6.7), o [AutorizacionInsuficienteFailure] si el
  /// llamante no es superadministrador (Req 5.4).
  Future<void> deleteUser(String userId);

  /// Restablece el Bono del Usuario fijando su Saldo_De_Clases en diez (10)
  /// (Req 6.5). Lanza [AutorizacionInsuficienteFailure] si no está autorizado.
  Future<void> restablecerBono(String userId);

  /// Ajusta el Saldo_De_Clases del Usuario al [valor] indicado, que debe estar
  /// en el rango 0..10 (Req 6.6).
  ///
  /// Lanza [BonoFueraDeRangoFailure] si [valor] está fuera de 0..10, o
  /// [AutorizacionInsuficienteFailure] si el llamante no es superadministrador.
  Future<void> ajustarBono(String userId, int valor);

  /// Concede el rol de superadministrador al Usuario indicado respetando el
  /// máximo de dos (2) superadministradores del Sistema (Req 5.1, 5.2).
  ///
  /// Lanza [MaxSuperadminsFailure] si ya existen dos superadministradores
  /// (Req 5.2), o [AutorizacionInsuficienteFailure] si no está autorizado.
  Future<void> grantSuperadmin(String userId);
}
