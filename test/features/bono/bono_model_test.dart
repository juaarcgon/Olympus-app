// Prueba de propiedad del modelo puro del Bono.
//
// Feature: gym-management-app, Property 2
//
// Property 2: La invariante del saldo se mantiene en 0..10.
// "Para cualquier usuario y cualquier secuencia de operaciones de bono
//  (asistencia/consumo, reembolso, ajuste o restablecimiento por superadmin),
//  el saldo_clases resultante siempre cumple 0 <= saldo_clases <= 10."
//
// Validates: Requirements 4.4, 8.10
//
// La propiedad se verifica contra el modelo de dominio puro del bono
// (`consumir`, `reembolsar`, `ajustar`, `restablecer`), espejo de las RPC del
// backend, usando `glados` con un mínimo de 100 iteraciones. Cada iteración
// genera un saldo inicial arbitrario y una secuencia arbitraria de operaciones;
// la invariante 0..10 se comprueba tras CADA operación de la secuencia.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/bono/domain/bono_model.dart';

/// Operaciones de bono que puede contener una secuencia generada.
enum _OpTipo { consumir, reembolsar, ajustar, restablecer }

/// Una operación concreta de la secuencia.
///
/// [valor] solo es relevante para [_OpTipo.ajustar]; para el resto se ignora.
/// Se genera un rango deliberadamente amplio (incluyendo valores fuera de
/// 0..10) para ejercitar tanto el ajuste válido como su rechazo, verificando
/// que la invariante se mantiene en ambos casos.
class _Op {
  const _Op(this.tipo, this.valor);
  final _OpTipo tipo;
  final int valor;

  @override
  String toString() => tipo == _OpTipo.ajustar ? 'ajustar($valor)' : tipo.name;
}

/// Generador del tipo de operación (uniforme sobre las 4 operaciones).
Generator<_OpTipo> get _anyTipo =>
    any.positiveIntOrZero.map((n) => _OpTipo.values[n % _OpTipo.values.length]);

/// Generador del valor para `ajustar`, en un rango amplio (-5..15) que incluye
/// valores dentro y fuera del rango permitido 0..10.
Generator<int> get _anyValorAjuste => any.intInRange(-5, 16);

/// Generador de una operación: combina tipo y valor de ajuste.
Generator<_Op> get _anyOp =>
    any.combine2(_anyTipo, _anyValorAjuste, (tipo, valor) => _Op(tipo, valor));

/// Generador de una secuencia arbitraria de operaciones.
Generator<List<_Op>> get _anySecuencia => any.list(_anyOp);

/// Generador de un saldo inicial arbitrario, en un rango amplio (-5..15) para
/// ejercitar también entradas que el clamp debe corregir.
Generator<int> get _anySaldoInicial => any.intInRange(-5, 16);

/// Aplica una operación al [saldo] y devuelve el saldo resultante.
///
/// Para `consumir` y `ajustar` (que devuelven [BonoResult]) se usa el campo
/// `saldo` del resultado como siguiente saldo: en caso de rechazo conserva el
/// saldo previo, en caso de éxito el nuevo saldo.
int _aplicar(int saldo, _Op op) {
  switch (op.tipo) {
    case _OpTipo.consumir:
      return consumir(saldo).saldo;
    case _OpTipo.reembolsar:
      return reembolsar(saldo);
    case _OpTipo.ajustar:
      return ajustar(saldo, op.valor).saldo;
    case _OpTipo.restablecer:
      return restablecer();
  }
}

void main() {
  group(
    'Feature: gym-management-app, Property 2 - invariante del saldo 0..10',
    () {
      Glados2(
        _anySaldoInicial,
        _anySecuencia,
      ).test('para cualquier saldo inicial y secuencia de operaciones de bono, '
          'el saldo resultante permanece siempre en 0..10 (Req 4.4, 8.10)', (
        saldoInicial,
        secuencia,
      ) {
        // El clamp estricto garantiza la invariante desde el punto de partida,
        // aun cuando el saldo inicial generado esté fuera de rango.
        var saldo = clampSaldo(saldoInicial);
        expect(saldo, inInclusiveRange(kBonoMin, kBonoMax));

        for (final op in secuencia) {
          saldo = _aplicar(saldo, op);

          // Invariante central (Property 2 / Req 4.4, 8.10): tras CADA
          // operación el saldo permanece dentro del rango cerrado 0..10.
          expect(
            saldo,
            inInclusiveRange(kBonoMin, kBonoMax),
            reason: 'La operación $op dejó el saldo fuera de 0..10: $saldo',
          );
        }

        // Invariante final tras toda la secuencia.
        expect(saldo, inInclusiveRange(kBonoMin, kBonoMax));
      });
    },
  );
}
