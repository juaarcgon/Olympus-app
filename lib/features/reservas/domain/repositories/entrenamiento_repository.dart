// Contrato de dominio del plan de entrenamiento del día (EntrenamientoRepository).
//
// Define las operaciones sobre el plan de entrenamiento asociado a una fecha
// (tabla `entrenamiento_dia`):
//   - consultar el plan de una fecha concreta (lectura para cualquier Usuario
//     autenticado) (Req 8.1),
//   - guardar (upsert por fecha) la lista ordenada de actividades del día; esta
//     operación solo la puede realizar un superadministrador, restricción
//     reforzada por las políticas RLS de la migración 0007 (Req 8.2).
//
// La interfaz es independiente del SDK de Supabase para facilitar las pruebas;
// la implementación concreta vive en la capa de datos y traduce los errores
// técnicos a `Failure` de dominio.

import '../entities/entrenamiento_dia.dart';

/// Servicio del plan de entrenamiento del día (por fecha).
abstract class EntrenamientoRepository {
  /// Devuelve el plan de entrenamiento de la [fecha] indicada, o `null` si no
  /// hay plan asignado para ese día (Req 8.1).
  ///
  /// Solo se tiene en cuenta la parte de fecha (año/mes/día); la hora se
  /// ignora. Cualquier Usuario con sesión activa puede consultar el plan.
  Future<EntrenamientoDia?> getPorFecha(DateTime fecha);

  /// Guarda (upsert por `fecha`) la lista ordenada de [actividades] del día
  /// [fecha] y devuelve el plan persistido (Req 8.1, 8.2).
  ///
  /// Solo un superadministrador puede escribir el plan; un intento sin
  /// privilegios es rechazado por la RLS y se traduce a
  /// [AutorizacionInsuficienteFailure].
  Future<EntrenamientoDia> guardar(DateTime fecha, List<String> actividades);
}
