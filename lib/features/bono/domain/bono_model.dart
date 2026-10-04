// Modelo de dominio puro del Bono para la app Olympus.
//
// Reúne las operaciones de negocio del `saldo_clases` del bono como funciones
// puras en memoria: sin efectos secundarios, sin dependencias de Supabase y
// completamente deterministas. Son el espejo exacto de las funciones RPC del
// backend (`reservar_clase`, `cancelar_reserva`, `ajustar_bono`,
// `restablecer_bono`) descritas en el diseño ("Servicio_Bono"; "Funciones RPC
// del backend"), de modo que puedan validarse con pruebas basadas en
// propiedades y usarse como referencia en las pruebas de integración.
//
// Invariante central (Property 2 / Req 4.4, 8.10): el saldo resultante de
// cualquier operación permanece siempre dentro del rango cerrado
// [kBonoMin, kBonoMax] == 0..10. El clamp se aplica de forma estricta.

import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/failures.dart';

/// Resultado de una operación del bono que puede ser rechazada.
///
/// Modela de forma pura (sin lanzar excepciones) el desenlace de operaciones
/// como [consumir] o [ajustar], que pueden fallar por reglas de negocio. Se
/// prefiere un tipo resultado explícito frente a excepciones para mantener las
/// funciones puras y fácilmente verificables.
///
/// - En caso de éxito, [saldo] contiene el nuevo saldo (dentro de 0..10) y
///   [failure] es `null`.
/// - En caso de rechazo, [failure] contiene el error de dominio y [saldo]
///   conserva el saldo original sin modificar (la operación no tiene efecto).
///
/// Inmutable; implementa igualdad estructural por valor.
class BonoResult {
  const BonoResult._({required this.saldo, this.failure});

  /// Crea un resultado exitoso con el [saldo] resultante.
  const BonoResult.ok(int saldo) : this._(saldo: saldo);

  /// Crea un resultado rechazado con el [failure] y el [saldo] sin cambios.
  const BonoResult.rechazo(Failure failure, int saldo)
    : this._(saldo: saldo, failure: failure);

  /// Saldo de clases tras la operación. En caso de rechazo es el saldo previo.
  final int saldo;

  /// Error de dominio si la operación fue rechazada; `null` si tuvo éxito.
  final Failure? failure;

  /// Indica si la operación se completó con éxito.
  bool get esExito => failure == null;

  /// Indica si la operación fue rechazada por una regla de negocio.
  bool get esRechazo => failure != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BonoResult &&
          runtimeType == other.runtimeType &&
          saldo == other.saldo &&
          failure == other.failure);

  @override
  int get hashCode => Object.hash(saldo, failure);

  @override
  String toString() => failure == null
      ? 'BonoResult.ok(saldo: $saldo)'
      : 'BonoResult.rechazo($failure, saldo: $saldo)';
}

/// Fija [saldo] estrictamente dentro del rango cerrado [kBonoMin, kBonoMax].
///
/// Garantiza la invariante del bono 0..10 (Property 2 / Req 4.4, 8.10). Es la
/// base del "clamp estricto" aplicado por el resto de operaciones.
int clampSaldo(int saldo) {
  if (saldo < kBonoMin) return kBonoMin;
  if (saldo > kBonoMax) return kBonoMax;
  return saldo;
}

/// Consume una (1) clase del bono (espejo de `reservar_clase`).
///
/// Si [saldo] es mayor que cero, decrementa el saldo exactamente en 1
/// (Req 4.2) y devuelve un [BonoResult.ok] con el nuevo saldo. Si [saldo] es
/// cero (no quedan clases), rechaza la operación con [SinClasesFailure] sin
/// modificar el saldo (Req 4.3).
///
/// El resultado nunca cae por debajo de [kBonoMin] (Req 4.4, 8.10).
BonoResult consumir(int saldo) {
  final actual = clampSaldo(saldo);
  if (actual <= kBonoMin) {
    return BonoResult.rechazo(const SinClasesFailure(), actual);
  }
  return BonoResult.ok(clampSaldo(actual - 1));
}

/// Reembolsa una (1) clase al bono (espejo del reembolso de `cancelar_reserva`).
///
/// Incrementa el saldo en 1 pero sin superar nunca [kBonoMax] == 10
/// (invariante del saldo, Req 8.10). Si el saldo ya está en el máximo,
/// permanece en 10.
int reembolsar(int saldo) {
  final actual = clampSaldo(saldo);
  return clampSaldo(actual + 1);
}

/// Ajusta el saldo del bono a [valor] (espejo de `ajustar_bono`).
///
/// Fija el saldo exactamente a [valor] si y solo si `0 <= valor <= 10`
/// (Req 6.6) y devuelve un [BonoResult.ok]. Si [valor] queda fuera del rango
/// 0..10, rechaza la operación con [ValorBonoFueraDeRangoFailure] y conserva
/// el saldo previo sin modificar.
BonoResult ajustar(int saldo, int valor) {
  final previo = clampSaldo(saldo);
  if (valor < kBonoMin || valor > kBonoMax) {
    return BonoResult.rechazo(const ValorBonoFueraDeRangoFailure(), previo);
  }
  return BonoResult.ok(valor);
}

/// Restablece el bono a su valor completo (espejo de `restablecer_bono`).
///
/// Fija el saldo en [kBonoMax] == 10 con independencia del saldo previo
/// (Req 6.5).
int restablecer() => kBonoMax;

/// El valor solicitado para ajustar el bono está fuera del rango 0..10 (Req 6.6).
///
/// Fallo de validación de dominio específico de la operación [ajustar]: se
/// produce cuando se intenta fijar el saldo a un valor que no pertenece al
/// rango cerrado [kBonoMin, kBonoMax]. Es público para poder verificarse en
/// las pruebas de la propiedad del ajuste.
class ValorBonoFueraDeRangoFailure extends Failure {
  const ValorBonoFueraDeRangoFailure([
    super.mensaje = 'El saldo debe estar entre 0 y 10',
  ]);
}
