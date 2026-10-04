// Contrato de dominio del Servicio_Bono (BonoRepository).
//
// Define la unica operacion que un Usuario con Sesion activa realiza
// directamente sobre su propio Bono desde el cliente: consultar su
// Saldo_De_Clases actual (Req 4.1).
//
// La modificacion del saldo nunca ocurre por `update` directo del cliente:
// siempre a traves de funciones RPC del backend (`reservar_clase`,
// `cancelar_reserva`, `ajustar_bono`, `restablecer_bono`). Las operaciones
// administrativas de ajuste/restablecimiento pertenecen al AdminRepository
// (tareas posteriores), por lo que este contrato se mantiene limitado a la
// lectura del saldo, acorde al diseno "Servicio_Bono".
//
// La interfaz es independiente del SDK de Supabase para facilitar las pruebas
// y futuras sustituciones; la implementacion concreta vive en la capa de datos.

/// Servicio_Bono: lectura del saldo de clases del Usuario autenticado.
abstract class BonoRepository {
  /// Devuelve el Saldo_De_Clases actual del Usuario autenticado (Req 4.1).
  ///
  /// Lanza un `Failure` de dominio si no hay sesion activa o si la consulta no
  /// devuelve ninguna fila (p. ej. por las politicas RLS).
  Future<int> getSaldo();
}
