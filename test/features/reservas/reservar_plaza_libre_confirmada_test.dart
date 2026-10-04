// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 23
//
// Property 23: Reserva con plaza libre crea confirmada y descuenta exactamente 1.
// "Para cualquier clase cuyo aforo no está completo y cualquier usuario con
//  saldo_clases > 0, reservar crea una Reserva_Confirmada para ese usuario y
//  deja saldo_clases' == saldo_clases - 1."
//
// Validates: Requirements 8.3
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.reservar`), espejo de la RPC `reservar_clase` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase cuyo aforo NO está completo (hay al menos una plaza libre) y un usuario
// nuevo con saldo estrictamente mayor que cero (1..10). Comprueba que
// `reservar`:
//   - tiene éxito (no hay rechazo con aforo libre y saldo > 0),
//   - produce una Reserva_Confirmada (ReservaOutcome.confirmada),
//   - deja al usuario en la lista de confirmadas de la clase,
//   - deja el saldo resultante en exactamente `saldo - 1`.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/entities/entities.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de una clase con plaza libre y un usuario con saldo > 0.
///
/// Modela fielmente la precondición de la propiedad: `aforo` es el aforo de la
/// Clase (1..10), `plazasOcupadas` es el número de Reservas_Confirmadas previas
/// (0..aforo-1, por lo que siempre queda al menos una plaza libre) y `saldo`
/// es el saldo de clases del Usuario que reserva (1..10, estrictamente > 0).
class _EscenarioPlazaLibre {
  const _EscenarioPlazaLibre(this.aforo, this.plazasOcupadas, this.saldo);

  final int aforo;
  final int plazasOcupadas;
  final int saldo;

  @override
  String toString() =>
      '_EscenarioPlazaLibre(aforo: $aforo, plazasOcupadas: $plazasOcupadas, '
      'saldo: $saldo)';
}

/// Generador de escenarios con aforo NO completo y saldo del usuario > 0.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `plazasOcupadas` en 0..aforo-1, garantizando `aforoCompleto == false`.
/// - `saldo` en 1..kBonoMax (10), garantizando `saldo_clases > 0`.
Generator<_EscenarioPlazaLibre> get _anyEscenarioPlazaLibre => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(0, aforo)
          .bind(
            (plazasOcupadas) => any
                .intInRange(kBonoMin + 1, kBonoMax + 1)
                .map(
                  (saldo) => _EscenarioPlazaLibre(aforo, plazasOcupadas, saldo),
                ),
          ),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 23 - reserva con plaza libre crea '
    'confirmada y descuenta 1',
    () {
      Glados(_anyEscenarioPlazaLibre).test(
        'para cualquier clase con aforo libre y usuario con saldo > 0, '
        'reservar crea confirmada y deja saldo - 1 (Req 8.3)',
        (escenario) {
          // Ids de los usuarios ya confirmados y del usuario que reserva.
          final confirmadas = List.generate(
            escenario.plazasOcupadas,
            (i) => 'ocupante$i',
          );
          const usuario = 'reservante';

          // Los ocupantes previos tienen saldo arbitrario; el usuario que
          // reserva tiene el saldo generado (> 0).
          final saldos = <String, int>{
            for (final id in confirmadas) id: kBonoMax,
            usuario: escenario.saldo,
          };

          final estado = ReservasEstado(
            aforo: escenario.aforo,
            saldos: saldos,
            confirmadas: confirmadas,
          );

          // Precondiciones de la propiedad.
          expect(
            estado.aforoCompleto,
            isFalse,
            reason: 'el escenario debe tener al menos una plaza libre',
          );
          expect(estado.saldoDe(usuario), greaterThan(0));

          final res = estado.reservar(usuario);

          // Con aforo libre y saldo > 0 la reserva nunca se rechaza.
          expect(
            res.esExito,
            isTrue,
            reason: 'reservar debería tener éxito con aforo libre y saldo > 0',
          );

          // La solicitud crea una Reserva_Confirmada (status 'confirmada').
          expect(res.resultado!.outcome, ReservaOutcome.confirmada);
          expect(res.resultado!.esConfirmada, isTrue);

          // El usuario queda registrado como confirmado en la clase.
          expect(res.estado.confirmadas, contains(usuario));

          // Invariante central (Property 23 / Req 8.3): el saldo resultante es
          // exactamente el previo menos 1.
          expect(
            res.resultado!.saldoResultante,
            escenario.saldo - 1,
            reason: 'reservar debería dejar el saldo en ${escenario.saldo - 1}',
          );
          expect(res.estado.saldoDe(usuario), escenario.saldo - 1);
        },
      );
    },
  );
}
