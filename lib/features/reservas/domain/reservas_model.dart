// Modelo puro (en memoria) de reservas, lista de espera y promoción para la
// app Olympus.
//
// Replica la lógica de las funciones RPC del backend `reservar_clase` y
// `cancelar_reserva` (ver design.md, "Funciones RPC del backend" y "Tabla
// reservas") como un modelo de dominio puro, inmutable y sin dependencia de
// Supabase. Esto permite verificar la lógica de aforo, lista de espera FIFO,
// duplicados, reembolso según antelación y promoción atómica mediante pruebas
// unitarias y de propiedad rápidas y deterministas.
//
// Invariantes modeladas:
// - Aforo: el número de reservas confirmadas nunca supera `aforo` (≤ 10).
// - Lista de espera: nunca supera `kWaitlistMax` (20) entradas (Req 8.12).
// - Unicidad: un usuario figura como máximo una vez (confirmada o espera)
//   por clase (Req 8.6).
// - Saldo: cada saldo de usuario permanece en el rango 0..10 (Req 8.10).

import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/domain/entities/reserva_result.dart';

/// Restringe [valor] al rango permitido del bono (0..10) (Req 8.10).
///
/// Función pura y autocontenida: no depende del modelo de bono de otra feature
/// para evitar acoplamientos de compilación.
int _clampSaldo(int valor) {
  if (valor < kBonoMin) return kBonoMin;
  if (valor > kBonoMax) return kBonoMax;
  return valor;
}

/// Estado inmutable en memoria de una única Clase.
///
/// Modela el conjunto de reservas y la lista de espera de la Clase junto con
/// el saldo de clases (bono) de cada Usuario implicado. Es la fuente de verdad
/// sobre la que operan [reservar] y [cancelar], que devuelven siempre un nuevo
/// estado sin mutar el actual.
class ReservasEstado {
  /// Crea un estado de reservas.
  ///
  /// Copia defensivamente las colecciones recibidas para garantizar la
  /// inmutabilidad del estado.
  ReservasEstado({
    required this.aforo,
    required Map<String, int> saldos,
    List<String> confirmadas = const <String>[],
    List<String> espera = const <String>[],
  }) : saldos = Map<String, int>.unmodifiable(saldos),
       confirmadas = List<String>.unmodifiable(confirmadas),
       espera = List<String>.unmodifiable(espera);

  /// Aforo máximo de plazas confirmadas de la Clase (1..10, Req 8.1).
  final int aforo;

  /// Saldo de clases (bono) de cada Usuario, indexado por su id.
  ///
  /// Un usuario no presente se trata como saldo cero (0).
  final Map<String, int> saldos;

  /// Ids de los Usuarios con Reserva_Confirmada, en orden de confirmación.
  final List<String> confirmadas;

  /// Ids de los Usuarios en la Lista_De_Espera, en orden FIFO (Req 8.5, 8.9).
  final List<String> espera;

  /// Número de plazas confirmadas ocupadas.
  int get plazasOcupadas => confirmadas.length;

  /// Indica si el Aforo está completo.
  bool get aforoCompleto => confirmadas.length >= aforo;

  /// Devuelve el saldo del Usuario [userId]; cero (0) si no se conoce.
  int saldoDe(String userId) => saldos[userId] ?? 0;

  /// Indica si [userId] ya tiene una reserva o figura en la lista de espera.
  bool tieneEntrada(String userId) =>
      confirmadas.contains(userId) || espera.contains(userId);

  /// Posición FIFO (1-indexada) de [userId] en la lista de espera; `null` si
  /// no está en espera.
  int? posicionEspera(String userId) {
    final indice = espera.indexOf(userId);
    return indice == -1 ? null : indice + 1;
  }

  /// Reserva una plaza para [usuario] (replica `reservar_clase`).
  ///
  /// Reglas (Req 8.3, 8.4, 8.5, 8.6, 8.12):
  /// - Si el saldo del usuario es cero (0): se rechaza con [SinClasesFailure]
  ///   sin crear reserva ni entrada en espera (Req 8.4).
  /// - Si el usuario ya tiene reserva o está en espera: se rechaza con
  ///   [ReservaDuplicadaFailure] sin duplicar (Req 8.6).
  /// - Si hay aforo libre y saldo > 0: crea Reserva_Confirmada y descuenta
  ///   exactamente 1 del saldo (Req 8.3).
  /// - Si el aforo está completo, saldo > 0 y la espera tiene < 20 entradas:
  ///   añade al final de la lista de espera (FIFO) sin tocar el saldo (Req 8.5).
  /// - Si el aforo está completo y la espera ya tiene 20 entradas: se rechaza
  ///   con [ListaEsperaLlenaFailure] (Req 8.12).
  ///
  /// Devuelve un [ReservarResult] con el nuevo estado y el desenlace o fallo.
  ReservarResult reservar(String usuario) {
    // Req 8.4: sin clases en el bono -> rechazo sin efectos.
    if (saldoDe(usuario) <= 0) {
      return ReservarResult.fallo(this, const SinClasesFailure());
    }

    // Req 8.6: no se permiten reservas ni entradas de espera duplicadas.
    if (tieneEntrada(usuario)) {
      return ReservarResult.fallo(this, const ReservaDuplicadaFailure());
    }

    // Req 8.3: hay aforo libre -> confirmada y descuento de 1 clase.
    if (!aforoCompleto) {
      final nuevoSaldo = _clampSaldo(saldoDe(usuario) - 1);
      final nuevoEstado = _copyWith(
        saldos: {...saldos, usuario: nuevoSaldo},
        confirmadas: [...confirmadas, usuario],
      );
      return ReservarResult.exito(
        nuevoEstado,
        ReservaResult.confirmada(saldoResultante: nuevoSaldo),
      );
    }

    // Aforo completo. Req 8.12: lista de espera llena -> rechazo.
    if (espera.length >= kWaitlistMax) {
      return ReservarResult.fallo(this, const ListaEsperaLlenaFailure());
    }

    // Req 8.5: aforo completo con hueco en espera -> al final (FIFO), sin
    // modificar el saldo.
    final nuevaEspera = [...espera, usuario];
    final nuevoEstado = _copyWith(espera: nuevaEspera);
    return ReservarResult.exito(
      nuevoEstado,
      ReservaResult.enEspera(
        posicion: nuevaEspera.length,
        saldoResultante: saldoDe(usuario),
      ),
    );
  }

  /// Cancela la participación de [usuario] en la Clase (replica
  /// `cancelar_reserva`).
  ///
  /// [antelacionHoras] son las horas que faltan hasta el Horario_Clase en el
  /// momento de la cancelación.
  ///
  /// Reglas (Req 8.7, 8.8, 8.9, 8.11):
  /// - Si el usuario tiene Reserva_Confirmada: libera la plaza; reembolsa +1
  ///   al saldo si `antelacionHoras >= kCancelacionHoras` (2h) y no lo modifica
  ///   en caso contrario (Req 8.7, 8.8). A continuación, de forma atómica,
  ///   promociona al primer usuario de la espera con saldo > 0 a confirmada,
  ///   descontándole 1 (FIFO, Req 8.9).
  /// - Si el usuario está en la lista de espera: elimina su entrada sin tocar
  ///   su saldo (Req 8.11).
  /// - Si el usuario no participa en la Clase: no hay efectos.
  ///
  /// Devuelve un [CancelarResult] con el nuevo estado y el detalle de la
  /// operación.
  CancelarResult cancelar(String usuario, {required num antelacionHoras}) {
    // Req 8.11: cancelación de una entrada en lista de espera.
    if (espera.contains(usuario)) {
      final nuevaEspera = espera.where((id) => id != usuario).toList();
      final nuevoEstado = _copyWith(espera: nuevaEspera);
      return CancelarResult(
        estado: nuevoEstado,
        liberoPlaza: false,
        huboReembolso: false,
        promocionado: null,
      );
    }

    // Si no tiene reserva confirmada, no hay nada que cancelar.
    if (!confirmadas.contains(usuario)) {
      return CancelarResult(
        estado: this,
        liberoPlaza: false,
        huboReembolso: false,
        promocionado: null,
      );
    }

    // Reserva confirmada: liberar la plaza (Req 8.7/8.8).
    final nuevosSaldos = <String, int>{...saldos};
    final nuevasConfirmadas = confirmadas.where((id) => id != usuario).toList();

    // Reembolso solo con antelación >= 2h (Req 8.7); sin reembolso si < 2h
    // (Req 8.8). El saldo se mantiene en el rango 0..10 (Req 8.10).
    final huboReembolso = antelacionHoras >= kCancelacionHoras;
    if (huboReembolso) {
      nuevosSaldos[usuario] = _clampSaldo((nuevosSaldos[usuario] ?? 0) + 1);
    }

    // Req 8.9: promoción atómica del primer usuario de la espera con saldo > 0.
    var nuevaEspera = [...espera];
    String? promocionado;
    for (var i = 0; i < nuevaEspera.length; i++) {
      final candidato = nuevaEspera[i];
      if ((nuevosSaldos[candidato] ?? 0) > 0) {
        promocionado = candidato;
        nuevaEspera.removeAt(i);
        nuevasConfirmadas.add(candidato);
        nuevosSaldos[candidato] = _clampSaldo(
          (nuevosSaldos[candidato] ?? 0) - 1,
        );
        break;
      }
    }

    final nuevoEstado = _copyWith(
      saldos: nuevosSaldos,
      confirmadas: nuevasConfirmadas,
      espera: nuevaEspera,
    );
    return CancelarResult(
      estado: nuevoEstado,
      liberoPlaza: true,
      huboReembolso: huboReembolso,
      promocionado: promocionado,
    );
  }

  /// Devuelve una copia del estado con las colecciones indicadas reemplazadas.
  ReservasEstado _copyWith({
    int? aforo,
    Map<String, int>? saldos,
    List<String>? confirmadas,
    List<String>? espera,
  }) {
    return ReservasEstado(
      aforo: aforo ?? this.aforo,
      saldos: saldos ?? this.saldos,
      confirmadas: confirmadas ?? this.confirmadas,
      espera: espera ?? this.espera,
    );
  }

  @override
  String toString() =>
      'ReservasEstado(aforo: $aforo, confirmadas: $confirmadas, '
      'espera: $espera, saldos: $saldos)';
}

/// Resultado de [ReservasEstado.reservar].
///
/// Contiene el nuevo [estado] (siempre no nulo; coincide con el estado previo
/// cuando la operación se rechaza) y, de forma mutuamente excluyente, el
/// [resultado] de la reserva en caso de éxito o el [failure] en caso de rechazo.
class ReservarResult {
  const ReservarResult._({required this.estado, this.resultado, this.failure});

  /// Crea un resultado de reserva exitosa (confirmada o en espera).
  const ReservarResult.exito(ReservasEstado estado, ReservaResult resultado)
    : this._(estado: estado, resultado: resultado);

  /// Crea un resultado de reserva rechazada; el estado no cambia.
  const ReservarResult.fallo(ReservasEstado estado, Failure failure)
    : this._(estado: estado, failure: failure);

  /// Estado resultante de la operación.
  final ReservasEstado estado;

  /// Detalle del desenlace cuando la reserva tuvo éxito; `null` si fue rechazo.
  final ReservaResult? resultado;

  /// Fallo de dominio cuando la reserva fue rechazada; `null` si tuvo éxito.
  final Failure? failure;

  /// Indica si la operación tuvo éxito.
  bool get esExito => failure == null;

  @override
  String toString() => esExito
      ? 'ReservarResult.exito($resultado)'
      : 'ReservarResult.fallo($failure)';
}

/// Resultado de [ReservasEstado.cancelar].
///
/// Describe el nuevo [estado] y los efectos de la cancelación: si se liberó una
/// plaza confirmada ([liberoPlaza]), si hubo reembolso de 1 clase
/// ([huboReembolso], Req 8.7/8.8) y el id del usuario promocionado desde la
/// lista de espera, si lo hubo ([promocionado], Req 8.9).
class CancelarResult {
  const CancelarResult({
    required this.estado,
    required this.liberoPlaza,
    required this.huboReembolso,
    required this.promocionado,
  });

  /// Estado resultante tras la cancelación.
  final ReservasEstado estado;

  /// Indica si se liberó una plaza confirmada.
  final bool liberoPlaza;

  /// Indica si la cancelación conllevó reembolso de 1 clase (antelación ≥ 2h).
  final bool huboReembolso;

  /// Id del usuario promocionado desde la espera; `null` si no hubo promoción.
  final String? promocionado;

  @override
  String toString() =>
      'CancelarResult(liberoPlaza: $liberoPlaza, huboReembolso: '
      '$huboReembolso, promocionado: $promocionado)';
}
