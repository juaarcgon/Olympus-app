// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 24
//
// Property 24: Reserva en clase llena añade al final de la lista de espera sin
// tocar el saldo.
// "Para cualquier clase con aforo completo cuya lista de espera tiene menos de
//  veinte (20) entradas, y cualquier usuario con saldo_clases > 0 sin reserva
//  previa, reservar añade al usuario al final de la lista de espera (orden
//  FIFO) y deja su saldo_clases sin cambios."
//
// Validates: Requirements 8.5
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.reservar`), espejo de la RPC `reservar_clase` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase cuyo aforo YA está completo (confirmadas == aforo), una lista de espera
// previa con 0..19 entradas (estrictamente menor que kWaitlistMax = 20) y un
// usuario nuevo con saldo estrictamente mayor que cero (1..10). Comprueba que
// `reservar`:
//   - tiene éxito (aforo completo con hueco en espera y saldo > 0 no se
//     rechaza),
//   - produce una entrada en Lista_De_Espera (ReservaOutcome.enEspera),
//   - coloca al usuario en la ÚLTIMA posición de la espera (FIFO: tras los que
//     ya esperaban, preservando su orden relativo),
//   - deja el saldo del usuario SIN cambios (igual al previo).

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/entities/entities.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de una clase con aforo completo y hueco en la lista de espera.
///
/// Modela la precondición de la propiedad: `aforo` es el aforo de la Clase
/// (1..10) y, al estar completo, hay exactamente `aforo` reservas confirmadas;
/// `enEsperaPrevia` es el número de entradas que ya existen en la lista de
/// espera (0..19, estrictamente < kWaitlistMax = 20, por lo que siempre queda
/// hueco); `saldo` es el saldo de clases del Usuario que reserva (1..10,
/// estrictamente > 0).
class _EscenarioClaseLlena {
  const _EscenarioClaseLlena(this.aforo, this.enEsperaPrevia, this.saldo);

  final int aforo;
  final int enEsperaPrevia;
  final int saldo;

  @override
  String toString() =>
      '_EscenarioClaseLlena(aforo: $aforo, enEsperaPrevia: $enEsperaPrevia, '
      'saldo: $saldo)';
}

/// Generador de escenarios con aforo completo, espera con hueco y saldo > 0.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `enEsperaPrevia` en 0..kWaitlistMax-1 (0..19), garantizando que la espera
///   no está llena (`espera.length < kWaitlistMax`).
/// - `saldo` en 1..kBonoMax (10), garantizando `saldo_clases > 0`.
Generator<_EscenarioClaseLlena> get _anyEscenarioClaseLlena => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(0, kWaitlistMax)
          .bind(
            (enEsperaPrevia) => any
                .intInRange(kBonoMin + 1, kBonoMax + 1)
                .map(
                  (saldo) => _EscenarioClaseLlena(aforo, enEsperaPrevia, saldo),
                ),
          ),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 24 - reserva en clase llena añade '
    'al final de la espera sin tocar el saldo',
    () {
      Glados(_anyEscenarioClaseLlena).test(
        'para cualquier clase con aforo completo, espera con hueco y usuario '
        'con saldo > 0, reservar añade al final de la espera (FIFO) y no toca '
        'el saldo (Req 8.5)',
        (escenario) {
          // Clase completa: tantas confirmadas como aforo.
          final confirmadas = List.generate(
            escenario.aforo,
            (i) => 'ocupante$i',
          );
          // Lista de espera previa, en orden FIFO conocido.
          final esperaPrevia = List.generate(
            escenario.enEsperaPrevia,
            (i) => 'espera$i',
          );
          const usuario = 'reservante';

          // Saldos arbitrarios para ocupantes y previos; el usuario que reserva
          // tiene el saldo generado (> 0).
          final saldos = <String, int>{
            for (final id in confirmadas) id: kBonoMax,
            for (final id in esperaPrevia) id: kBonoMax,
            usuario: escenario.saldo,
          };

          final estado = ReservasEstado(
            aforo: escenario.aforo,
            saldos: saldos,
            confirmadas: confirmadas,
            espera: esperaPrevia,
          );

          // Precondiciones de la propiedad.
          expect(
            estado.aforoCompleto,
            isTrue,
            reason: 'el escenario debe tener el aforo completo',
          );
          expect(
            estado.espera.length,
            lessThan(kWaitlistMax),
            reason: 'la espera debe tener hueco (< $kWaitlistMax)',
          );
          expect(estado.saldoDe(usuario), greaterThan(0));
          expect(
            estado.tieneEntrada(usuario),
            isFalse,
            reason: 'el usuario no debe tener reserva previa',
          );

          final res = estado.reservar(usuario);

          // Con aforo completo, hueco en espera y saldo > 0 no hay rechazo.
          expect(
            res.esExito,
            isTrue,
            reason:
                'reservar debería tener éxito con clase llena, hueco en '
                'espera y saldo > 0',
          );

          // La solicitud se añade a la Lista_De_Espera (no confirmada).
          expect(res.resultado!.outcome, ReservaOutcome.enEspera);
          expect(res.resultado!.enEspera, isTrue);

          // Invariante FIFO (Property 24 / Req 8.5): el usuario queda en la
          // ÚLTIMA posición, tras los que ya esperaban, preservando su orden.
          final nuevaEspera = res.estado.espera;
          expect(nuevaEspera.length, esperaPrevia.length + 1);
          expect(
            nuevaEspera.last,
            usuario,
            reason: 'el usuario debe quedar al final de la lista de espera',
          );
          expect(
            nuevaEspera.sublist(0, esperaPrevia.length),
            orderedEquals(esperaPrevia),
            reason: 'el orden FIFO de los que ya esperaban se preserva',
          );
          // Posición FIFO 1-indexada reportada y real coinciden con el final.
          expect(res.resultado!.posicion, nuevaEspera.length);
          expect(res.estado.posicionEspera(usuario), nuevaEspera.length);

          // Invariante central (Property 24 / Req 8.5): el saldo NO cambia.
          expect(
            res.resultado!.saldoResultante,
            escenario.saldo,
            reason: 'entrar en espera no debe modificar el saldo',
          );
          expect(res.estado.saldoDe(usuario), escenario.saldo);
        },
      );
    },
  );
}
