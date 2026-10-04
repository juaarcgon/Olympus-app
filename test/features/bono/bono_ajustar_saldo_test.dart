// Prueba de propiedad del modelo puro del Bono.
//
// Feature: gym-management-app, Property 17
//
// Property 17: Ajustar el saldo fija el valor solicitado y rechaza fuera de
// rango.
// "Para cualquier valor entero en el rango 0..10, ajustar el saldo de un
//  usuario deja saldo_clases == valor; para cualquier valor fuera de 0..10 la
//  operación se rechaza y el saldo no cambia."
//
// Validates: Requirements 6.6
//
// La propiedad se verifica contra el modelo de dominio puro del bono
// (`ajustar`), espejo de la RPC `ajustar_bono` del backend, usando `glados`
// con un mínimo de 100 iteraciones. Se cubren las dos ramas de la propiedad:
//   - valor dentro de 0..10: `ajustar` tiene éxito y fija el saldo en `valor`;
//   - valor fuera de 0..10: `ajustar` se rechaza con
//     `ValorBonoFueraDeRangoFailure` y conserva el saldo previo (clamp) sin
//     modificar.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/bono/domain/bono_model.dart';

/// Generador de un saldo previo arbitrario. Rango amplio que incluye valores
/// dentro de la invariante del bono (0..10) y fuera de ella (negativos y
/// superiores a 10) para expresar fielmente "cualquier saldo previo".
Generator<int> get _anySaldoPrevio => any.intInRange(-20, 21);

/// Generador de un valor de ajuste dentro del rango cerrado 0..10.
Generator<int> get _anyValorEnRango => any.intInRange(kBonoMin, kBonoMax + 1);

/// Generador de un valor de ajuste fuera del rango 0..10 (negativos y > 10).
///
/// Se genera un entero sobre un rango amplio contiguo y se mapea para excluir
/// por construcción el intervalo prohibido 0..10, cubriendo ambos extremos:
///   - `n` en -20..-1 se mantiene como valor negativo fuera de rango;
///   - `n` en 0..19 se desplaza a 11..30 (fuera de rango por arriba).
/// Usa solo `intInRange` y `.map`, combinadores ya empleados en las pruebas
/// hermanas.
Generator<int> get _anyValorFueraDeRango =>
    any.intInRange(-20, 20).map((n) => n < 0 ? n : kBonoMax + 1 + n);

void main() {
  group('Feature: gym-management-app, Property 17 - ajustar fija el valor y '
      'rechaza fuera de rango', () {
    Glados2(_anySaldoPrevio, _anyValorEnRango).test(
      'para cualquier valor en 0..10, ajustar tiene éxito y deja el saldo en '
      'exactamente valor (Req 6.6)',
      (saldoPrevio, valor) {
        // Precondición de esta rama: el valor pertenece al rango 0..10.
        expect(valor, inInclusiveRange(kBonoMin, kBonoMax));

        final resultado = ajustar(saldoPrevio, valor);

        // Con un valor dentro de rango, el ajuste nunca se rechaza.
        expect(
          resultado.esExito,
          isTrue,
          reason:
              'ajustar($saldoPrevio, $valor) debería tener éxito con un '
              'valor dentro de 0..10',
        );

        // Invariante central (Property 17 / Req 6.6): el saldo queda fijado
        // exactamente en el valor solicitado.
        expect(
          resultado.saldo,
          valor,
          reason:
              'ajustar($saldoPrevio, $valor) debería dejar el saldo en $valor',
        );
      },
    );

    Glados2(_anySaldoPrevio, _anyValorFueraDeRango).test(
      'para cualquier valor fuera de 0..10, ajustar se rechaza y el saldo no '
      'cambia (Req 6.6)',
      (saldoPrevio, valor) {
        // Precondición de esta rama: el valor está fuera del rango 0..10.
        expect(valor < kBonoMin || valor > kBonoMax, isTrue);

        final resultado = ajustar(saldoPrevio, valor);

        // Un valor fuera de rango siempre provoca el rechazo de la operación.
        expect(
          resultado.esRechazo,
          isTrue,
          reason:
              'ajustar($saldoPrevio, $valor) debería rechazarse con un valor '
              'fuera de 0..10',
        );
        expect(resultado.failure, isA<ValorBonoFueraDeRangoFailure>());

        // Invariante central (Property 17 / Req 6.6): ante un rechazo el
        // saldo conserva el valor previo (tras el clamp a 0..10) sin cambio.
        expect(
          resultado.saldo,
          clampSaldo(saldoPrevio),
          reason:
              'ajustar($saldoPrevio, $valor) rechazado debería conservar el '
              'saldo previo sin modificar',
        );
      },
    );
  });
}
