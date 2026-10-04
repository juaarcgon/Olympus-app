// Contrato de dominio del Servicio_Reservas (ReservasRepository).
//
// Define las operaciones del calendario de Clases y de la gestión de Reservas:
//   - consultar el calendario de Clases, opcionalmente acotado por rango de
//     fechas (Req 8.1),
//   - crear, editar y eliminar Clases; estas operaciones solo las puede
//     realizar un superadministrador, restricción reforzada por las políticas
//     RLS de PostgreSQL (migración 0003) (Req 8.1, 8.2),
//   - reservar y cancelar la participación del Usuario de la sesión en una
//     Clase, delegando en RPC transaccionales del backend para resistir la
//     concurrencia (Req 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.11, 8.12).
//
// La interfaz es independiente del SDK de Supabase para facilitar las pruebas
// y futuras sustituciones; la implementación concreta vive en la capa de datos
// y traduce los errores técnicos a `Failure` de dominio.

import '../entities/apuntado.dart';
import '../entities/clase.dart';
import '../entities/ocupacion_clase.dart';
import '../entities/reserva.dart';
import '../entities/reserva_result.dart';

/// Servicio_Reservas: calendario de Clases y gestión de Reservas.
abstract class ReservasRepository {
  /// Devuelve el calendario de Clases ordenado por horario ascendente (Req 8.1).
  ///
  /// Si se indica [desde], incluye solo Clases con `horario >= desde`; si se
  /// indica [hasta], incluye solo Clases con `horario <= hasta`. Cualquier
  /// Usuario con Sesión activa puede consultar el calendario (política RLS de
  /// `SELECT`).
  Future<List<Clase>> getCalendario({DateTime? desde, DateTime? hasta});

  /// Crea una nueva Clase y devuelve la entidad persistida (Req 8.1).
  ///
  /// Solo un superadministrador puede crear Clases (Req 8.2); un intento sin
  /// privilegios es rechazado por la RLS y se traduce a
  /// [AutorizacionInsuficienteFailure]. El [aforo] debe respetar la invariante
  /// 1..10 que garantiza el `CHECK` de la tabla.
  Future<Clase> crearClase({
    required DateTime horario,
    required int aforo,
    required String monitor,
  });

  /// Edita los campos indicados de la Clase [claseId] y devuelve la entidad
  /// actualizada (Req 8.1).
  ///
  /// Solo se modifican los parámetros proporcionados (no nulos); los omitidos
  /// conservan su valor actual. Solo un superadministrador puede editar Clases
  /// (Req 8.2); de lo contrario se lanza [AutorizacionInsuficienteFailure].
  Future<Clase> editarClase(
    String claseId, {
    DateTime? horario,
    int? aforo,
    String? monitor,
  });

  /// Elimina la Clase [claseId] (Req 8.1).
  ///
  /// Solo un superadministrador puede eliminar Clases (Req 8.2); de lo
  /// contrario se lanza [AutorizacionInsuficienteFailure].
  Future<void> eliminarClase(String claseId);

  /// Reserva una plaza para el Usuario de la sesión en la Clase [claseId] y
  /// devuelve el desenlace (confirmada o en lista de espera).
  ///
  /// Delega en la RPC atómica `reservar_clase` del backend. Puede lanzar:
  ///   - [SinClasesFailure] si no quedan clases en el bono (Req 8.4),
  ///   - [ReservaDuplicadaFailure] si ya existe una reserva/espera (Req 8.6),
  ///   - [ListaEsperaLlenaFailure] si la lista de espera está completa
  ///     (Req 8.12),
  ///   - [AutorizacionInsuficienteFailure] si no hay sesión activa (Req 7.3).
  Future<ReservaResult> reservar(String claseId);

  /// Cancela la participación del Usuario de la sesión en la Clase [claseId]
  /// (Req 8.7, 8.8, 8.9, 8.11).
  ///
  /// Delega en la RPC atómica `cancelar_reserva` del backend, que libera la
  /// plaza, aplica el reembolso según la antelación y promociona de la lista de
  /// espera cuando corresponde. Lanza [AutorizacionInsuficienteFailure] si no
  /// hay sesión activa (Req 7.3).
  Future<void> cancelar(String claseId);

  /// Devuelve la ocupación agregada de la Clase [claseId]: número de reservas
  /// confirmadas y en lista de espera, sin exponer identidades (Req 8.1).
  ///
  /// Se apoya en la RPC de solo lectura `ocupacion_clase` (migración 0008), que
  /// cualquier Usuario autenticado puede ejecutar; permite mostrar el aforo
  /// real "confirmadas/aforo" aunque la RLS de `reservas` solo deje al Usuario
  /// normal ver sus propias filas.
  Future<OcupacionClase> getOcupacion(String claseId);

  /// Devuelve la lista nominal de Usuarios apuntados a la Clase [claseId],
  /// ordenada por estado y posición (Req 8.2).
  ///
  /// SOLO debe usarse para el superadministrador: la RLS de `reservas`
  /// restringe esta lectura a sus propias filas para un Usuario normal, por lo
  /// que la lista completa de apuntados únicamente es visible para el
  /// superadministrador.
  Future<List<Apuntado>> getApuntados(String claseId);

  /// Devuelve las reservas propias del Usuario de la sesión para las Clases
  /// [claseIds], indexadas por `claseId`.
  ///
  /// Gracias a la RLS de `reservas` (política de `SELECT` sobre filas propias),
  /// cada Usuario solo obtiene sus propias reservas. Permite a la UI reflejar
  /// el estado de la reserva del Usuario en cada franja (confirmada / en espera
  /// / sin reserva). Las Clases sin reserva del Usuario no aparecen en el mapa.
  Future<Map<String, Reserva>> getMisReservas(List<String> claseIds);
}
