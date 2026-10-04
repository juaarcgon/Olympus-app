// Prueba de propiedad del modelo puro del Bono.
//
// Feature: gym-management-app, Property 11
//
// Property 11: El consumo de bono decrementa exactamente en 1.
// "Para cualquier usuario con saldo_clases > 0, registrar la asistencia a una
//  clase deja saldo_clases' == saldo_clases - 1."
//
// Validates: Requirements 4.2
//
// La propiedad se verifica contra el modelo de dominio puro del bono
// (`consumir`), espejo de la RPC `reservar_clase` del backend, usando `glados`
// con un mínimo de 100 iteraciones. Cada iteración genera un saldo arbitrario
// estrictamente mayor que cero (rango 1..10) y comprueba que `consumir`:
//   - devuelve un resultado exitoso (no hay rechazo mientras hay clases),
//   - deja el saldo resultante en exactamente `saldo - 1`.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/bono/domain/bono_model.dart';

/// Generador de un saldo con clases disponibles, en el rango cerrado 1..10
/// (saldo_clases > 0). El límite superior respeta la invariante del bono
/// [kBonoMax] == 10; el inferior garantiza la precondición saldo > 0.
Generator<int> get _anySaldoConClases =>
    any.intInRange(kBonoMin + 1, kBonoMax + 1);

void main() {
  group(
    'Feature: gym-management-app, Property 11 - el consumo decrementa en 1',
    () {
      Glados(_anySaldoConClases).test(
        'para cualquier saldo > 0, consumir deja el saldo en exactamente '
        'saldo - 1 (Req 4.2)',
        (saldo) {
          // Precondición de la propiedad: hay clases disponibles.
          expect(saldo, inInclusiveRange(kBonoMin + 1, kBonoMax));

          final resultado = consumir(saldo);

          // Mientras queda saldo, el consumo nunca se rechaza.
          expect(
            resultado.esExito,
            isTrue,
            reason: 'consumir($saldo) debería tener éxito con saldo > 0',
          );

          // Invariante central (Property 11 / Req 4.2): el decremento es
          // exactamente de 1 clase.
          expect(
            resultado.saldo,
            saldo - 1,
            reason: 'consumir($saldo) debería dejar el saldo en ${saldo - 1}',
          );
        },
      );
    },
  );
}
