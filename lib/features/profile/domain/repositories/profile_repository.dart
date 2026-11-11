// Contrato de dominio del Servicio_Usuarios (ProfileRepository).
//
// Define las operaciones que un Usuario con Sesion activa puede realizar sobre
// su propio perfil: consultarlo (Req 3.1) y actualizar sus campos editables
// (nombre, apellidos y foto) (Req 3.2).
//
// Deliberadamente NO expone métodos para modificar `saldo_clases` ni `estado`:
// el usuario estándar no puede alterar esos valores (Req 3.3, 3.4). Esta
// restricción se refuerza, además, con las políticas RLS de PostgreSQL
// (migración 0003_rls.sql), que impiden escribir esas columnas desde el
// cliente aunque la capa de datos lo intentara.
//
// La interfaz es independiente del SDK de Supabase para facilitar las pruebas
// y futuras sustituciones; la implementación concreta vive en la capa de datos.

import 'package:image_picker/image_picker.dart';

import '../entities/profile.dart';

/// Servicio_Usuarios: lectura y actualización del perfil propio.
abstract class ProfileRepository {
  /// Devuelve el perfil del Usuario autenticado actual (Req 3.1).
  ///
  /// Permite consultar nombre, apellidos, foto, correo electrónico y
  /// Saldo_De_Clases del propio Usuario. Lanza un [Failure] de dominio si no
  /// hay sesión activa o si la consulta no devuelve ninguna fila.
  Future<Profile> getMyProfile();

  /// Actualiza los campos editables del perfil del Usuario autenticado y
  /// devuelve el perfil ya actualizado (Req 3.2).
  ///
  /// Solo se modifican los parámetros proporcionados (no nulos); los campos
  /// omitidos conservan su valor actual. Si se proporciona [foto], se sube al
  /// bucket de Storage y se asocia su URL al perfil (Req 1.7).
  ///
  /// Esta operación nunca modifica `saldo_clases` ni `estado` (Req 3.3, 3.4);
  /// el modelo ampliable preserva íntegramente `metadata` (Req 3.5).
  Future<Profile> updateMyProfile({
    String? nombre,
    String? apellidos,
    XFile? foto,
  });

  /// Elimina de forma permanente la cuenta del Usuario autenticado y cierra
  /// su sesión (exigido por Google Play).
  ///
  /// Borra la foto de perfil, libera sus plazas en clases futuras (pasan al
  /// siguiente de la lista de espera) y borra la cuenta de acceso con todos
  /// sus datos. Lanza un [Failure] si no se puede completar; en ese caso la
  /// cuenta sigue existiendo. Un superadministrador no puede eliminarse así.
  Future<void> eliminarMiCuenta();
}
