// Providers de Riverpod para el Servicio_Reservas (calendario y reservas).
//
// Esta capa de estado (Application) orquesta los casos de uso del calendario de
// Clases y del plan de entrenamiento del día sobre los repositorios de dominio,
// y expone estados inmutables de carga/éxito/error que la UI observa:
//
//   - [reservasRepositoryProvider]: inyecta la implementación del
//     [ReservasRepository] ([ReservasRepositoryImpl]).
//   - [entrenamientoRepositoryProvider]: inyecta la implementación del
//     [EntrenamientoRepository] ([EntrenamientoRepositoryImpl]).
//   - [diaSeleccionadoProvider]: `Notifier` con el día elegido en el calendario
//     (fecha local a medianoche). La UI lo actualiza al tocar un día.
//   - [DiaReservasNotifier] / [diaReservasProvider]: `AsyncNotifier` familiar
//     por fecha que carga, para el día dado, las franjas horarias (Clases) de
//     ese día, el plan de entrenamiento y la ocupación de cada franja, además
//     de la reserva propia del Usuario; expone un [DiaReservasView] agregado y
//     los comandos [DiaReservasNotifier.reservar] /
//     [DiaReservasNotifier.cancelar] (Req 8.1, 8.3, 8.5, 8.7).
//
// Ref. diseño: "Servicio_Reservas"; "Capas del cliente Flutter".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/entrenamiento_repository_impl.dart';
import '../../data/repositories/reservas_repository_impl.dart';
import '../../domain/entities/clase.dart';
import '../../domain/entities/entrenamiento_dia.dart';
import '../../domain/entities/ocupacion_clase.dart';
import '../../domain/entities/reserva_result.dart';
import '../../domain/repositories/entrenamiento_repository.dart';
import '../../domain/repositories/reservas_repository.dart';
import 'dia_reservas_view.dart';

/// Provee la implementación del [ReservasRepository] (Servicio_Reservas).
///
/// Por defecto construye un [ReservasRepositoryImpl] respaldado por Supabase.
/// En pruebas puede sobrescribirse con un doble mediante
/// `reservasRepositoryProvider.overrideWithValue(...)`.
final reservasRepositoryProvider = Provider<ReservasRepository>(
  (ref) => ReservasRepositoryImpl(),
);

/// Provee la implementación del [EntrenamientoRepository] (plan del día).
///
/// Por defecto construye un [EntrenamientoRepositoryImpl] respaldado por
/// Supabase. En pruebas puede sobrescribirse con `overrideWithValue(...)`.
final entrenamientoRepositoryProvider = Provider<EntrenamientoRepository>(
  (ref) => EntrenamientoRepositoryImpl(),
);

/// `Notifier` con el día seleccionado en el calendario (fecha a medianoche).
///
/// Mantiene únicamente la parte de fecha (año/mes/día), normalizada a
/// medianoche local, para que el [diaReservasProvider] se reconstruya solo
/// cuando cambia el día y no al variar la hora.
class DiaSeleccionadoNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _soloFecha(DateTime.now());

  /// Fija el día seleccionado (se normaliza a medianoche local).
  void seleccionar(DateTime fecha) => state = _soloFecha(fecha);
}

/// Expone el día seleccionado en el calendario.
final diaSeleccionadoProvider =
    NotifierProvider<DiaSeleccionadoNotifier, DateTime>(
      DiaSeleccionadoNotifier.new,
    );

/// `AsyncNotifier` que carga la vista agregada del día seleccionado (Req 8.1).
///
/// Observa [diaSeleccionadoProvider] en `build`, de modo que se reconstruye
/// automáticamente al cambiar el día en el calendario. Compone, en una sola
/// carga: las franjas horarias (Clases) cuyo horario cae en
/// `[fecha 00:00, fecha 23:59:59]`, el plan de entrenamiento del día, la
/// ocupación de cada franja (RPC `ocupacion_clase`) y la reserva propia del
/// Usuario en cada franja. Expone un [DiaReservasView] y los comandos de
/// reserva/cancelación, que refrescan el estado tras completarse (Req 8.3,
/// 8.5, 8.7).
class DiaReservasNotifier extends AsyncNotifier<DiaReservasView> {
  @override
  Future<DiaReservasView> build() {
    // Reacciona al día seleccionado: cualquier cambio reconstruye la vista.
    _fecha = ref.watch(diaSeleccionadoProvider);
    return _cargar();
  }

  late DateTime _fecha;

  /// Carga y compone la vista del día desde los repositorios de dominio.
  Future<DiaReservasView> _cargar() async {
    final reservasRepo = ref.read(reservasRepositoryProvider);
    final entrenamientoRepo = ref.read(entrenamientoRepositoryProvider);

    // Rango del día completo [00:00, 23:59:59.999] (Req 8.1).
    final desde = _fecha;
    final hasta = _fecha.add(
      const Duration(hours: 23, minutes: 59, seconds: 59, milliseconds: 999),
    );

    // Clases del día y plan de entrenamiento, en paralelo.
    final resultados = await Future.wait<Object?>([
      reservasRepo.getCalendario(desde: desde, hasta: hasta),
      entrenamientoRepo.getPorFecha(_fecha),
    ]);

    final clases = resultados[0] as List<Clase>;
    final plan = resultados[1] as EntrenamientoDia?;

    final claseIds = clases.map((c) => c.id).toList(growable: false);

    // Ocupación de cada franja y reservas propias, en paralelo.
    final ocupaciones = await Future.wait<OcupacionClase>(
      clases.map((c) => reservasRepo.getOcupacion(c.id)),
    );
    final misReservas = await reservasRepo.getMisReservas(claseIds);

    final franjas = <FranjaReserva>[];
    for (var i = 0; i < clases.length; i++) {
      final clase = clases[i];
      final ocupacion = ocupaciones[i];
      franjas.add(
        FranjaReserva(
          clase: clase,
          confirmadas: ocupacion.confirmadas,
          espera: ocupacion.espera,
          miReserva: misReservas[clase.id],
        ),
      );
    }

    return DiaReservasView(fecha: _fecha, plan: plan, franjas: franjas);
  }

  /// Reserva una plaza en la Clase [claseId] y refresca el día (Req 8.3, 8.5).
  ///
  /// Devuelve el [ReservaResult] en caso de éxito para que la UI muestre el
  /// mensaje adecuado. Propaga los `Failure` de dominio (p. ej.
  /// [SinClasesFailure]) sin alterar el estado del día.
  Future<ReservaResult> reservar(String claseId) async {
    final repo = ref.read(reservasRepositoryProvider);
    final resultado = await repo.reservar(claseId);
    await refrescar();
    return resultado;
  }

  /// Cancela la reserva del Usuario en la Clase [claseId] y refresca el día
  /// (Req 8.7). Propaga los `Failure` de dominio sin alterar el estado.
  Future<void> cancelar(String claseId) async {
    final repo = ref.read(reservasRepositoryProvider);
    await repo.cancelar(claseId);
    await refrescar();
  }

  // --- Gestión del superadministrador (Req 8.1, 8.2) --------------------------
  //
  // Las operaciones de creación/edición/eliminación de Clases y de guardado del
  // plan del día solo las puede realizar un superadministrador; la restricción
  // la refuerzan las políticas RLS del backend, que traducen un intento sin
  // privilegios a [AutorizacionInsuficienteFailure]. Estos comandos propagan
  // los `Failure` de dominio sin alterar el estado y, tras completarse con
  // éxito, refrescan la vista del día.

  /// Crea una nueva franja horaria (Clase) en el día y refresca (Req 8.1).
  ///
  /// El [horario] combina la fecha del día seleccionado con la hora elegida por
  /// el superadministrador; el [aforo] respeta la invariante 1..10 y [monitor]
  /// es el nombre del monitor asignado. Propaga los `Failure` de dominio.
  Future<void> crearFranja({
    required DateTime horario,
    required int aforo,
    required String monitor,
  }) async {
    final repo = ref.read(reservasRepositoryProvider);
    await repo.crearClase(horario: horario, aforo: aforo, monitor: monitor);
    await refrescar();
  }

  /// Edita los campos indicados de la franja [claseId] y refresca (Req 8.1).
  ///
  /// Solo se modifican los parámetros no nulos; los omitidos conservan su valor
  /// actual. Propaga los `Failure` de dominio sin alterar el estado.
  Future<void> editarFranja(
    String claseId, {
    DateTime? horario,
    int? aforo,
    String? monitor,
  }) async {
    final repo = ref.read(reservasRepositoryProvider);
    await repo.editarClase(
      claseId,
      horario: horario,
      aforo: aforo,
      monitor: monitor,
    );
    await refrescar();
  }

  /// Elimina la franja [claseId] del día y refresca (Req 8.1).
  ///
  /// Propaga los `Failure` de dominio sin alterar el estado.
  Future<void> eliminarFranja(String claseId) async {
    final repo = ref.read(reservasRepositoryProvider);
    await repo.eliminarClase(claseId);
    await refrescar();
  }

  /// Guarda (upsert) el plan de entrenamiento del día y refresca (Req 8.1, 8.2).
  ///
  /// Usa la fecha del día seleccionado del propio notifier; la lista de
  /// [actividades] es la nueva lista ordenada del plan. Propaga los `Failure`
  /// de dominio sin alterar el estado.
  Future<void> guardarPlan(List<String> actividades) async {
    final repo = ref.read(entrenamientoRepositoryProvider);
    await repo.guardar(_fecha, actividades);
    await refrescar();
  }

  /// Vuelve a cargar la vista del día desde el backend (Req 8.1).
  Future<void> refrescar() async {
    state = const AsyncValue<DiaReservasView>.loading();
    state = await AsyncValue.guard(_cargar);
  }
}

/// Expone la vista agregada del día seleccionado (carga/éxito/error).
final diaReservasProvider =
    AsyncNotifierProvider<DiaReservasNotifier, DiaReservasView>(
      DiaReservasNotifier.new,
    );

/// Normaliza una [DateTime] a su fecha local a medianoche (sin hora).
DateTime _soloFecha(DateTime fecha) =>
    DateTime(fecha.year, fecha.month, fecha.day);
