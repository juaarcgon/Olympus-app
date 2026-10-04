// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 25
//
// Property 25: No se permiten reservas ni entradas de espera duplicadas.
// "Para cualquier usuario que ya tiene una reserva o figura en la lista de
//  espera de una clase, un nuevo intento de reservar esa clase se rechaza y no
//  crea una entrada duplicada (como máximo una fila por par usuario-clase)."
//
// Validates: Requirements 8.6
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.reservar`), espejo de la RPC `reservar_clase` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase y coloca al usuario que reserva, YA, en una de dos posiciones previas:
//   - como Reserva_Confirmada, o
//   - como entrada en la Lista_De_Espera,
// con saldo arbitrario (0..10) para cubrir también el caso en que el usuario
// tendría saldo suficiente para una reserva nueva. Comprueba que un segundo
// `reservar` del mismo usuario:
//   - se rechaza (ReservarResult.esExito == false) con ReservaDuplicadaFailure
//     (Req 8.6: el rechazo tiene prioridad incluso sobre la comprobación de
//     saldo),
//   - NO crea una entrada duplicada: el usuario sigue figurando exactamente una
//     vez (como máximo una fila por par usuario-clase) y en el mismo rol
//     (confirmada o espera) que antes,
//   - deja el estado sin cambios (confirmadas, espera y saldos idénticos).

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Rol previo del usuario que ya participa en la clase.
enum _RolPrevio { confirmada, espera }

/// Escenario en el que el usuario YA figura en la clase (confirmada o espera).
///
/// Modela la precondición de la propiedad: el usuario ya tiene una entrada por
/// la clase, de modo que un nuevo `reservar` debe rechazarse como duplicado.
///
/// - `aforo` es el aforo de la Clase (1..10).
/// - `rol` indica si el usuario ya está confirmado o en espera.
/// - `otrasConfirmadas` es el número de OTROS usuarios confirmados (0..aforo-1,
///   dejando sitio para el propio usuario cuando su rol es confirmada).
/// - `otrosEnEspera` es el número de OTROS usuarios en la espera (0..18, para
///   que quepa el propio usuario sin superar kWaitlistMax = 20).
/// - `saldo` es el saldo de clases del usuario (0..10, arbitrario: el rechazo
///   por duplicado debe ocurrir incluso con saldo suficiente).
class _EscenarioDuplicado {
  const _EscenarioDuplicado(
    this.aforo,
    this.rol,
    this.otrasConfirmadas,
    this.otrosEnEspera,
    this.saldo,
  );

  final int aforo;
  final _RolPrevio rol;
  final int otrasConfirmadas;
  final int otrosEnEspera;
  final int saldo;

  @override
  String toString() =>
      '_EscenarioDuplicado(aforo: $aforo, rol: $rol, '
      'otrasConfirmadas: $otrasConfirmadas, otrosEnEspera: $otrosEnEspera, '
      'saldo: $saldo)';
}

/// Generador de escenarios en los que el usuario ya participa en la clase.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `rol` confirmada o espera (derivado de un entero 0/1).
/// - `otrasConfirmadas` en 0..aforo-1 (deja un hueco por si el rol es
///   confirmada; nunca supera el aforo).
/// - `otrosEnEspera` en 0..kWaitlistMax-2 (0..18), para que la espera siga
///   teniendo hueco tras incluir al propio usuario.
/// - `saldo` en 0..kBonoMax (0..10), arbitrario.
Generator<_EscenarioDuplicado> get _anyEscenarioDuplicado => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(0, 2)
          .bind(
            (rolBit) => any
                .intInRange(0, aforo)
                .bind(
                  (otrasConfirmadas) => any
                      .intInRange(0, kWaitlistMax - 1)
                      .bind(
                        (otrosEnEspera) => any
                            .intInRange(kBonoMin, kBonoMax + 1)
                            .map(
                              (saldo) => _EscenarioDuplicado(
                                aforo,
                                rolBit == 0
                                    ? _RolPrevio.confirmada
                                    : _RolPrevio.espera,
                                otrasConfirmadas,
                                otrosEnEspera,
                                saldo,
                              ),
                            ),
                      ),
                ),
          ),
    );

void main() {
  group('Feature: gym-management-app, Property 25 - no se permiten reservas ni '
      'entradas de espera duplicadas', () {
    Glados(_anyEscenarioDuplicado).test(
      'para cualquier usuario que ya tiene reserva o figura en la espera, un '
      'nuevo reservar se rechaza y no crea un duplicado (Req 8.6)',
      (escenario) {
        const usuario = 'reservante';

        // Otros participantes de la clase (distintos del usuario).
        final otrasConfirmadas = List.generate(
          escenario.otrasConfirmadas,
          (i) => 'confirmado$i',
        );
        final otrosEnEspera = List.generate(
          escenario.otrosEnEspera,
          (i) => 'espera$i',
        );

        // Insertamos al usuario en el rol previo correspondiente.
        final confirmadasPrevias = <String>[...otrasConfirmadas];
        final esperaPrevia = <String>[...otrosEnEspera];
        if (escenario.rol == _RolPrevio.confirmada) {
          confirmadasPrevias.add(usuario);
        } else {
          esperaPrevia.add(usuario);
        }

        final saldos = <String, int>{
          for (final id in otrasConfirmadas) id: kBonoMax,
          for (final id in otrosEnEspera) id: kBonoMax,
          usuario: escenario.saldo,
        };

        final estado = ReservasEstado(
          aforo: escenario.aforo,
          saldos: saldos,
          confirmadas: confirmadasPrevias,
          espera: esperaPrevia,
        );

        // Precondición de la propiedad: el usuario ya figura exactamente una
        // vez en la clase (confirmada o espera).
        expect(
          estado.tieneEntrada(usuario),
          isTrue,
          reason: 'el usuario debe tener una entrada previa en la clase',
        );
        final aparicionesPrevias =
            confirmadasPrevias.where((id) => id == usuario).length +
            esperaPrevia.where((id) => id == usuario).length;
        expect(
          aparicionesPrevias,
          1,
          reason: 'el usuario debe figurar exactamente una vez antes',
        );

        final res = estado.reservar(usuario);

        // Invariante central de Property 25 (Req 8.6): el nuevo intento se
        // RECHAZA siempre (nunca tiene éxito) y no produce un resultado de
        // reserva.
        expect(
          res.esExito,
          isFalse,
          reason:
              'un segundo reservar del mismo usuario debe rechazarse (no '
              'puede crear una entrada duplicada)',
        );
        expect(res.resultado, isNull);

        // Cuando el usuario tiene saldo > 0, la única razón de rechazo posible
        // es el duplicado, por lo que el fallo debe ser ReservaDuplicadaFailure
        // con el mensaje de reserva ya existente (Req 8.6). Con saldo == 0 el
        // rechazo igualmente ocurre (Req 8.4), pero Property 25 solo exige que
        // la solicitud se rechace sin crear duplicado, no un tipo de fallo
        // concreto en ese solapamiento.
        if (escenario.saldo > 0) {
          expect(
            res.failure,
            isA<ReservaDuplicadaFailure>(),
            reason:
                'con saldo > 0 el fallo debe indicar reserva duplicada '
                '(Req 8.6)',
          );
        }

        // No se crea una entrada duplicada: el usuario sigue figurando
        // exactamente una vez (como máximo una fila por par usuario-clase).
        final apariciones =
            res.estado.confirmadas.where((id) => id == usuario).length +
            res.estado.espera.where((id) => id == usuario).length;
        expect(
          apariciones,
          1,
          reason:
              'el usuario debe figurar como máximo una vez tras el '
              'rechazo',
        );

        // El estado no cambia: mismas confirmadas, misma espera y mismos
        // saldos que antes del intento duplicado.
        expect(
          res.estado.confirmadas,
          orderedEquals(confirmadasPrevias),
          reason: 'las confirmadas no deben cambiar tras el rechazo',
        );
        expect(
          res.estado.espera,
          orderedEquals(esperaPrevia),
          reason: 'la lista de espera no debe cambiar tras el rechazo',
        );
        expect(
          res.estado.saldoDe(usuario),
          escenario.saldo,
          reason: 'el saldo no debe cambiar tras el rechazo',
        );
      },
    );
  });
}
