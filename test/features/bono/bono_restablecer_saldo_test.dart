// Prueba de propiedad del modelo puro del Bono.
//
// Feature: gym-management-app, Property 16
//
// Property 16: Restablecer el bono fija el saldo en 10.
// "Para cualquier usuario con cualquier saldo previo, restablecer su bono deja
//  saldo_clases == 10."
//
// Validates: Requirements 6.5
//
// La propiedad se verifica contra el modelo de dominio puro del bono
// (`restablecer`), espejo de la RPC `restablecer_bono` del backend, usando
// `glados` con un mínimo de 100 iteraciones. Cada iteración genera un saldo
// previo arbitrario (incluidos valores fuera del rango 0..10) y comprueba que
// el resultado de `restablecer` es siempre exactamente [kBonoMax] == 10, con
// total independencia de dicho saldo previo (Req 6.5).

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/bono/domain/bono_model.dart';

/// Generador de un saldo previo arbitrario. Se usa un rango amplio que incluye
/// valores dentro de la invariante del bono (0..10) y también fuera de ella
/// (negativos y superiores a 10) para expresar fielmente "cualquier saldo
/// previo": restablecer debe fijar el saldo en 10 sea cual sea el estado
/// anterior.
Generator<int> get _anySaldoPrevio => any.intInRange(-20, 21);

void main() {
  group(
    'Feature: gym-management-app, Property 16 - restablecer fija el saldo en 10',
    () {
      Glados(_anySaldoPrevio).test(
        'para cualquier saldo previo, restablecer deja el saldo en exactamente '
        '10 (Req 6.5)',
        (saldoPrevio) {
          // `restablecer` es independiente del saldo previo; el parámetro
          // generado representa el estado anterior arbitrario del usuario.
          final saldoResultante = restablecer();

          // Invariante central (Property 16 / Req 6.5): el saldo tras
          // restablecer es siempre exactamente 10, con independencia del
          // saldo previo $saldoPrevio.
          expect(
            saldoResultante,
            kBonoMax,
            reason:
                'restablecer() debería dejar el saldo en $kBonoMax sin importar '
                'el saldo previo ($saldoPrevio)',
          );
          expect(saldoResultante, 10);
        },
      );
    },
  );
}
