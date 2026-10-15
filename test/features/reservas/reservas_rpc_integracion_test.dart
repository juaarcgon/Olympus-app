// Pruebas de INTEGRACIÓN de las RPC de reservas contra el modelo de dominio
// puro (tarea 11.6).
//
// Objetivo
// --------
// Verificar que las funciones RPC reales de PostgreSQL `reservar_clase` y
// `cancelar_reserva` (migración `0006_rpc_reservas.sql`) producen EXACTAMENTE
// el mismo resultado observable que el modelo de dominio puro
// `ReservasEstado` (lib/features/reservas/domain/reservas_model.dart), incluida
// la CONDICIÓN DE CARRERA por la última plaza libre (dos usuarios reservando a
// la vez cuando solo queda una (1) plaza).
//   _Requirements: 8.3, 8.5, 8.9, 8.12_
//   _Design: Testing Strategy (pruebas de integración)_
//
// A diferencia del resto de la suite (que usa fakes en memoria sin red), estas
// pruebas requieren una INSTANCIA REAL de Supabase (preferiblemente local) con
// las migraciones aplicadas. Para no romper `flutter test` en entornos sin
// backend, el grupo entero se OMITE automáticamente salvo que se proporcionen
// las variables de entorno de conexión en tiempo de compilación.
//
// Cómo ejecutar estas pruebas (requiere Docker para `supabase start`)
// -------------------------------------------------------------------
//   1. Levantar Supabase local y aplicar las migraciones de `supabase/`:
//        supabase start
//        supabase db reset          # aplica supabase/migrations/*.sql
//   2. Anotar la API URL, la anon key y la SERVICE ROLE key que imprime
//      `supabase status` (o `supabase start`).
//   3. Ejecutar SOLO estas pruebas de integración pasando las variables:
//        flutter test test/features/reservas/reservas_rpc_integracion_test.dart \
//          --dart-define=INTEGRATION_SUPABASE=true \
//          --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//          --dart-define=SUPABASE_ANON_KEY=<anon-key> \
//          --dart-define=SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
//
// Sin `INTEGRATION_SUPABASE=true` (o sin las claves) el grupo se marca como
// `skip`, de modo que `flutter test` sigue en verde en CI/entornos sin
// Supabase. El código se compila y analiza igualmente (`flutter analyze`).
//
// Estrategia de comparación (RPC real vs. modelo puro)
// ----------------------------------------------------
// Cada escenario se ejecuta en PARALELO sobre dos "mundos":
//   * El mundo REAL: filas en PostgreSQL manipuladas con las RPC
//     `reservar_clase`/`cancelar_reserva` ejecutadas en nombre de cada usuario
//     (JWT propio), más lecturas de `profiles.saldo_clases` y de `reservas`.
//   * El mundo MODELO: un `ReservasEstado` en memoria sobre el que se aplican
//     las mismas operaciones (`reservar`/`cancelar`).
// Tras cada operación se comparan: desenlace (confirmada/espera/rechazo),
// posición en espera, saldo del usuario, conjunto de confirmados y cola de
// espera. Si ambos mundos coinciden en todos los escenarios, la RPC "refina"
// (coincide con) el modelo de dominio verificado por las pruebas de propiedad.

import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/domain/entities/reserva_result.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Configuración desde el entorno de compilación (--dart-define)
// ---------------------------------------------------------------------------

/// Interruptor maestro: si no es `true`, se OMITE todo el grupo de integración.
const bool kRunIntegration = bool.fromEnvironment(
  'INTEGRATION_SUPABASE',
  defaultValue: false,
);

/// URL de la API del proyecto Supabase (p. ej. `http://127.0.0.1:54321`).
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Clave anónima (publishable) del proyecto Supabase.
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Clave de servicio (service role) para operaciones de administración en las
/// pruebas (crear usuarios, crear clases, fijar saldos). NUNCA se usa en la app
/// real; solo en el arnés de pruebas de integración.
const String kSupabaseServiceRoleKey = String.fromEnvironment(
  'SUPABASE_SERVICE_ROLE_KEY',
);

/// Indica si hay configuración suficiente para ejecutar la integración.
bool get _integracionDisponible =>
    kRunIntegration &&
    kSupabaseUrl.isNotEmpty &&
    kSupabaseAnonKey.isNotEmpty &&
    kSupabaseServiceRoleKey.isNotEmpty;

/// Razón de omisión mostrada cuando falta configuración (o `false` si procede
/// ejecutar).
dynamic get _skipReason => _integracionDisponible
    ? false
    : 'Pruebas de integración de RPC omitidas: requieren una instancia de '
          'Supabase. Ejecuta con --dart-define=INTEGRATION_SUPABASE=true y las '
          'claves SUPABASE_URL/SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY '
          '(ver cabecera del archivo).';

void main() {
  group('RPC de reservas vs. modelo de dominio (integración)', () {
    // Arnés compartido: cliente admin (service role) para preparar datos.
    late SupabaseClient admin;

    // Identificadores de recursos creados, para su limpieza posterior.
    final idsUsuariosCreados = <String>[];
    final idsClasesCreadas = <String>[];

    setUpAll(() async {
      admin = SupabaseClient(
        kSupabaseUrl,
        kSupabaseServiceRoleKey,
        // Sin persistencia de sesión en pruebas.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });

    tearDownAll(() async {
      // Limpieza: eliminar clases (cascada borra reservas) y usuarios de auth.
      final harness = _IntegrationHarness(
        admin: admin,
        usuarios: idsUsuariosCreados,
        clases: idsClasesCreadas,
      );
      await harness.limpiar();
      await admin.dispose();
    });

    // -------------------------------------------------------------------
    // Escenario 1 — Plaza libre: confirmada y descuento exacto de 1 (Req 8.3)
    // -------------------------------------------------------------------
    test(
      'reservar con plaza libre: RPC coincide con el modelo (Req 8.3)',
      () async {
        final h = _IntegrationHarness(
          admin: admin,
          usuarios: idsUsuariosCreados,
          clases: idsClasesCreadas,
        );

        // Mundo REAL: clase con aforo 1 y un usuario con saldo 10.
        final clase = await h.crearClase(aforo: 1);
        final u = await h.crearUsuario(saldoInicial: 10);

        // Mundo MODELO: estado espejo.
        var modelo = ReservasEstado(aforo: 1, saldos: {u.id: 10});

        // Operación en ambos mundos.
        final real = await h.reservarReal(u, clase.id);
        final mod = modelo.reservar(u.id);
        modelo = mod.estado;

        // El modelo confirma y descuenta 1; la RPC debe coincidir.
        expect(mod.esExito, isTrue);
        expect(mod.resultado!.outcome, ReservaOutcome.confirmada);
        expect(mod.resultado!.saldoResultante, 9);

        expect(real.outcome, ReservaOutcome.confirmada);
        expect(real.saldoResultante, mod.resultado!.saldoResultante);

        // El saldo persistido en la base de datos coincide con el modelo.
        final saldoReal = await h.leerSaldo(u.id);
        expect(saldoReal, modelo.saldoDe(u.id));
        expect(saldoReal, 9);
      },
      skip: _skipReason,
    );

    // -------------------------------------------------------------------
    // Escenario 2 — Clase llena: segunda reserva va a espera (Req 8.5)
    // -------------------------------------------------------------------
    test(
      'clase llena: la 2ª reserva entra en espera igual que el modelo (Req 8.5)',
      () async {
        final h = _IntegrationHarness(
          admin: admin,
          usuarios: idsUsuariosCreados,
          clases: idsClasesCreadas,
        );

        final clase = await h.crearClase(aforo: 1);
        final u1 = await h.crearUsuario(saldoInicial: 10);
        final u2 = await h.crearUsuario(saldoInicial: 10);

        var modelo = ReservasEstado(aforo: 1, saldos: {u1.id: 10, u2.id: 10});

        // u1 confirma (ocupa la única plaza).
        final real1 = await h.reservarReal(u1, clase.id);
        modelo = modelo.reservar(u1.id).estado;
        expect(real1.outcome, ReservaOutcome.confirmada);

        // u2 reserva con aforo completo -> espera, posición 1, saldo intacto.
        final real2 = await h.reservarReal(u2, clase.id);
        final mod2 = modelo.reservar(u2.id);
        modelo = mod2.estado;

        expect(mod2.resultado!.outcome, ReservaOutcome.enEspera);
        expect(mod2.resultado!.posicion, 1);

        expect(real2.outcome, ReservaOutcome.enEspera);
        expect(real2.posicion, mod2.resultado!.posicion);

        // El saldo de u2 no cambia (sigue 10), igual que en el modelo.
        final saldoRealU2 = await h.leerSaldo(u2.id);
        expect(saldoRealU2, modelo.saldoDe(u2.id));
        expect(saldoRealU2, 10);
      },
      skip: _skipReason,
    );

    // -------------------------------------------------------------------
    // Escenario 3 — Lista de espera llena (20): se rechaza (Req 8.12)
    // -------------------------------------------------------------------
    test(
      'lista de espera con 20 entradas: la 21ª reserva se rechaza (Req 8.12)',
      () async {
        final h = _IntegrationHarness(
          admin: admin,
          usuarios: idsUsuariosCreados,
          clases: idsClasesCreadas,
        );

        final clase = await h.crearClase(aforo: 1);
        // 1 confirmado + 20 en espera = 21 usuarios con saldo > 0.
        final confirmador = await h.crearUsuario(saldoInicial: 10);
        final enEspera = <_TestUser>[];
        for (var i = 0; i < 20; i++) {
          enEspera.add(await h.crearUsuario(saldoInicial: 10));
        }
        final excedente = await h.crearUsuario(saldoInicial: 10);

        final saldosModelo = <String, int>{
          confirmador.id: 10,
          excedente.id: 10,
        };
        for (final u in enEspera) {
          saldosModelo[u.id] = 10;
        }
        var modelo = ReservasEstado(aforo: 1, saldos: saldosModelo);

        await h.reservarReal(confirmador, clase.id);
        modelo = modelo.reservar(confirmador.id).estado;

        for (final u in enEspera) {
          await h.reservarReal(u, clase.id);
          modelo = modelo.reservar(u.id).estado;
        }

        // La espera está llena (20). El modelo rechaza con ListaEsperaLlena.
        final mod = modelo.reservar(excedente.id);
        expect(mod.esExito, isFalse);
        expect(mod.failure, isA<ListaEsperaLlenaFailure>());

        // La RPC real también rechaza: el repositorio traduce a la misma Failure.
        await expectLater(
          h.reservarReal(excedente, clase.id),
          throwsA(isA<ListaEsperaLlenaFailure>()),
        );
      },
      skip: _skipReason,
    );

    // -------------------------------------------------------------------
    // Escenario 4 — Promoción FIFO al cancelar (Req 8.9)
    // -------------------------------------------------------------------
    test(
      'cancelar confirmada promociona al primero de la espera con saldo (Req 8.9)',
      () async {
        final h = _IntegrationHarness(
          admin: admin,
          usuarios: idsUsuariosCreados,
          clases: idsClasesCreadas,
        );

        // Clase futura (> 2h) para que la cancelación conlleve reembolso.
        final clase = await h.crearClase(aforo: 1, horasEnFuturo: 48);
        final titular = await h.crearUsuario(saldoInicial: 10);
        final espera1 = await h.crearUsuario(saldoInicial: 10);
        final espera2 = await h.crearUsuario(saldoInicial: 10);

        var modelo = ReservasEstado(
          aforo: 1,
          saldos: {titular.id: 10, espera1.id: 10, espera2.id: 10},
        );

        await h.reservarReal(titular, clase.id);
        modelo = modelo.reservar(titular.id).estado;
        await h.reservarReal(espera1, clase.id);
        modelo = modelo.reservar(espera1.id).estado;
        await h.reservarReal(espera2, clase.id);
        modelo = modelo.reservar(espera2.id).estado;

        // El titular cancela con antelación >= 2h -> reembolso y promoción FIFO.
        await h.cancelarReal(titular, clase.id);
        final modCancel = modelo.cancelar(titular.id, antelacionHoras: 48);
        modelo = modCancel.estado;

        // El modelo promociona a espera1 (primero de la cola).
        expect(modCancel.promocionado, espera1.id);
        expect(modCancel.huboReembolso, isTrue);

        // La realidad: espera1 pasa a confirmada; su saldo baja en 1 (10 -> 9).
        final apuntados = await h.leerApuntados(clase.id);
        expect(apuntados.confirmados, contains(espera1.id));
        expect(apuntados.confirmados, isNot(contains(titular.id)));

        final saldoPromocionado = await h.leerSaldo(espera1.id);
        expect(saldoPromocionado, modelo.saldoDe(espera1.id));
        expect(saldoPromocionado, 9);

        // El titular recupera su clase (reembolso): 10 -> 9 (reserva) -> 10.
        final saldoTitular = await h.leerSaldo(titular.id);
        expect(saldoTitular, modelo.saldoDe(titular.id));
        expect(saldoTitular, 10);
      },
      skip: _skipReason,
    );

    // -------------------------------------------------------------------
    // Escenario 5 — CONDICIÓN DE CARRERA por la última plaza
    // Dos usuarios reservan a la vez cuando solo queda 1 plaza. La RPC es
    // atómica (FOR UPDATE): exactamente uno queda confirmado y el otro en
    // espera. El modelo, aplicado secuencialmente en cualquier orden, produce
    // ese mismo reparto (1 confirmado + 1 en espera). (Req 8.3, 8.5)
    // -------------------------------------------------------------------
    test(
      'carrera por la última plaza: exactamente 1 confirmada y 1 en espera',
      () async {
        final h = _IntegrationHarness(
          admin: admin,
          usuarios: idsUsuariosCreados,
          clases: idsClasesCreadas,
        );

        final clase = await h.crearClase(aforo: 1);
        final a = await h.crearUsuario(saldoInicial: 10);
        final b = await h.crearUsuario(saldoInicial: 10);

        // Lanzar ambas reservas CONCURRENTEMENTE sobre la misma última plaza.
        // Cada una puede terminar en confirmada o en espera; nunca ambas
        // confirmadas (la RPC serializa con FOR UPDATE).
        final resultados = await Future.wait<ReservaResult?>([
          h.reservarRealOrNull(a, clase.id),
          h.reservarRealOrNull(b, clase.id),
        ]);

        final outcomes = resultados
            .whereType<ReservaResult>()
            .map((r) => r.outcome)
            .toList();

        // Invariante clave: exactamente una confirmada y una en espera.
        expect(
          outcomes.where((o) => o == ReservaOutcome.confirmada).length,
          1,
          reason: 'Solo un usuario puede ocupar la única plaza (atomicidad).',
        );
        expect(
          outcomes.where((o) => o == ReservaOutcome.enEspera).length,
          1,
          reason: 'El perdedor de la carrera queda en lista de espera.',
        );

        // El reparto coincide con el modelo aplicado en el orden que ganó la
        // carrera (comprobamos la invariante estructural, independiente del
        // orden): 1 confirmada en BD, 1 en espera, aforo no superado.
        final apuntados = await h.leerApuntados(clase.id);
        expect(apuntados.confirmados.length, 1);
        expect(apuntados.espera.length, 1);
        expect(apuntados.confirmados.length, lessThanOrEqualTo(clase.aforo));

        // El saldo del confirmado bajó a 9; el del que quedó en espera sigue 10.
        final ganador = apuntados.confirmados.single;
        final perdedor = apuntados.espera.single;
        expect(await h.leerSaldo(ganador), 9);
        expect(await h.leerSaldo(perdedor), 10);

        // Verificación cruzada con el modelo: aplicar ganador y luego perdedor
        // reproduce exactamente el estado real.
        var modelo = ReservasEstado(
          aforo: 1,
          saldos: {ganador: 10, perdedor: 10},
        );
        modelo = modelo.reservar(ganador).estado;
        modelo = modelo.reservar(perdedor).estado;
        expect(modelo.confirmadas.single, ganador);
        expect(modelo.espera.single, perdedor);
        expect(modelo.saldoDe(ganador), 9);
        expect(modelo.saldoDe(perdedor), 10);
      },
      skip: _skipReason,
    );
  });
}

// ===========================================================================
// Arnés de integración (solo pruebas)
// ===========================================================================

/// Usuario de prueba creado en Supabase Auth, con su email/contraseña y un
/// cliente propio autenticado (JWT del usuario) para invocar las RPC en su
/// nombre, respetando `auth.uid()`.
class _TestUser {
  _TestUser({required this.id, required this.email, required this.client});

  /// `profiles.id` / `auth.users.id`.
  final String id;

  /// Email del usuario de prueba.
  final String email;

  /// Cliente autenticado como este usuario (su propio JWT).
  final SupabaseClient client;
}

/// Instantánea de los apuntados de una Clase extraída de la base de datos.
class _Apuntados {
  _Apuntados({required this.confirmados, required this.espera});

  /// Ids de usuarios con reserva confirmada.
  final List<String> confirmados;

  /// Ids de usuarios en lista de espera, en orden FIFO (posición ascendente).
  final List<String> espera;
}

/// Clase de prueba creada en la base de datos.
class _TestClase {
  _TestClase({required this.id, required this.aforo});

  /// `clases.id`.
  final String id;

  /// Aforo de la Clase.
  final int aforo;
}

/// Arnés que prepara datos y ejecuta las operaciones de reserva/cancelación
/// contra una instancia REAL de Supabase, traduciendo las excepciones de la
/// RPC a los mismos `Failure` de dominio que el repositorio de producción, de
/// modo que la comparación con el modelo puro sea directa.
class _IntegrationHarness {
  _IntegrationHarness({
    required this.admin,
    required this.usuarios,
    required this.clases,
  });

  /// Cliente con service role (crea usuarios/clases, fija saldos, lee todo).
  final SupabaseClient admin;

  /// Acumulador de ids de usuarios creados (para limpieza).
  final List<String> usuarios;

  /// Acumulador de ids de clases creadas (para limpieza).
  final List<String> clases;

  final List<SupabaseClient> _clientesUsuario = <SupabaseClient>[];
  var _secuencia = 0;

  /// Crea una Clase con el [aforo] indicado y su horario [horasEnFuturo] horas
  /// por delante (por defecto 48h, suficiente para que la cancelación reembolse
  /// cuando el escenario lo requiera).
  Future<_TestClase> crearClase({
    required int aforo,
    int horasEnFuturo = 48,
  }) async {
    final horario = DateTime.now().toUtc().add(Duration(hours: horasEnFuturo));
    final row = await admin
        .from('clases')
        .insert(<String, dynamic>{
          'horario': horario.toIso8601String(),
          'aforo': aforo,
          'monitor': 'Monitor de pruebas',
        })
        .select()
        .single();
    final id = row['id'] as String;
    clases.add(id);
    return _TestClase(id: id, aforo: aforo);
  }

  /// Crea un usuario en Supabase Auth (confirmado), fija su `saldo_clases` a
  /// [saldoInicial] y devuelve un [_TestUser] con un cliente autenticado como
  /// él para invocar las RPC en su nombre.
  Future<_TestUser> crearUsuario({required int saldoInicial}) async {
    _secuencia += 1;
    final sufijo = '${DateTime.now().microsecondsSinceEpoch}_$_secuencia';
    final email = 'rpc_it_$sufijo@olympus.test';
    const password = 'password123';

    // Alta vía Admin API (email ya confirmado para poder iniciar sesión).
    final creado = await admin.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: password,
        emailConfirm: true,
        userMetadata: <String, dynamic>{
          'nombre': 'IT',
          'apellidos': 'Reservas',
        },
      ),
    );
    final id = creado.user!.id;
    usuarios.add(id);

    // El trigger `on_auth_user_created` crea el profile con saldo 10; se fija
    // el saldo inicial solicitado con service role.
    await admin
        .from('profiles')
        .update(<String, dynamic>{'saldo_clases': saldoInicial})
        .eq('id', id);

    // Cliente autenticado como el usuario (su propio JWT) para las RPC.
    final client = SupabaseClient(
      kSupabaseUrl,
      kSupabaseAnonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(email: email, password: password);
    _clientesUsuario.add(client);

    return _TestUser(id: id, email: email, client: client);
  }

  /// Fija el saldo del usuario [userId] con service role (espejo de ajustes de
  /// bono para montar escenarios concretos).
  Future<void> fijarSaldo(String userId, int saldo) async {
    await admin
        .from('profiles')
        .update(<String, dynamic>{'saldo_clases': saldo})
        .eq('id', userId);
  }

  /// Invoca la RPC real `reservar_clase` como [u] y mapea el jsonb a
  /// [ReservaResult], traduciendo los errores de negocio a `Failure`.
  Future<ReservaResult> reservarReal(_TestUser u, String claseId) async {
    try {
      final res = await u.client.rpc(
        'reservar_clase',
        params: <String, dynamic>{'p_clase_id': claseId},
      );
      final json = Map<String, dynamic>.from(res as Map);
      return _mapJsonToReservaResult(json);
    } on PostgrestException catch (e) {
      throw _mapReservarException(e);
    }
  }

  /// Igual que [reservarReal] pero devuelve `null` en caso de rechazo, para los
  /// escenarios de concurrencia donde ambos resultados son admisibles.
  Future<ReservaResult?> reservarRealOrNull(_TestUser u, String claseId) async {
    try {
      return await reservarReal(u, claseId);
    } on Failure {
      return null;
    }
  }

  /// Invoca la RPC real `cancelar_reserva` como [u].
  Future<void> cancelarReal(_TestUser u, String claseId) async {
    await u.client.rpc(
      'cancelar_reserva',
      params: <String, dynamic>{'p_clase_id': claseId},
    );
  }

  /// Lee `profiles.saldo_clases` del usuario [userId] con service role.
  Future<int> leerSaldo(String userId) async {
    final row = await admin
        .from('profiles')
        .select('saldo_clases')
        .eq('id', userId)
        .single();
    return (row['saldo_clases'] as num).toInt();
  }

  /// Lee los apuntados de la Clase (service role, salta RLS) separando
  /// confirmados y espera (esta última ordenada por posición FIFO).
  Future<_Apuntados> leerApuntados(String claseId) async {
    final rows = await admin
        .from('reservas')
        .select('user_id, status, posicion')
        .eq('clase_id', claseId)
        .order('posicion', ascending: true);
    final lista = List<Map<String, dynamic>>.from(rows);

    final confirmados = <String>[];
    final espera = <String>[];
    for (final r in lista) {
      final userId = r['user_id'] as String;
      if (r['status'] == 'confirmada') {
        confirmados.add(userId);
      } else {
        espera.add(userId);
      }
    }
    return _Apuntados(confirmados: confirmados, espera: espera);
  }

  /// Elimina las clases (cascada borra reservas), los usuarios de auth y cierra
  /// los clientes abiertos. Tolerante a errores para no enmascarar fallos de
  /// las aserciones.
  Future<void> limpiar() async {
    for (final claseId in clases) {
      try {
        await admin.from('clases').delete().eq('id', claseId);
      } catch (_) {
        // Ignorado: la limpieza es best-effort.
      }
    }
    clases.clear();

    for (final userId in usuarios) {
      try {
        await admin.auth.admin.deleteUser(userId);
      } catch (_) {
        // Ignorado: la limpieza es best-effort.
      }
    }
    usuarios.clear();

    for (final c in _clientesUsuario) {
      try {
        await c.dispose();
      } catch (_) {
        // Ignorado.
      }
    }
    _clientesUsuario.clear();
  }

  // --- Mapeos espejo del repositorio de producción -------------------------

  /// Mapea el jsonb de `reservar_clase` a [ReservaResult] (igual que el repo).
  ReservaResult _mapJsonToReservaResult(Map<String, dynamic> json) {
    final outcome = ReservaOutcome.desdeValor(json['status'] as String);
    final saldo = (json['saldo_resultante'] as num?)?.toInt() ?? 0;
    final posicionRaw = json['posicion'];
    final posicion = posicionRaw is num ? posicionRaw.toInt() : null;

    if (outcome == ReservaOutcome.enEspera) {
      return ReservaResult.enEspera(
        posicion: posicion ?? 0,
        saldoResultante: saldo,
      );
    }
    return ReservaResult.confirmada(saldoResultante: saldo);
  }

  /// Traduce la [PostgrestException] de `reservar_clase` al mismo `Failure` de
  /// dominio que `ReservasRepositoryImpl`, para comparar con el modelo.
  Failure _mapReservarException(PostgrestException e) {
    final mensaje = e.message;
    if (mensaje.contains('No quedan clases disponibles')) {
      return const SinClasesFailure();
    }
    if (mensaje.contains('Ya existe una reserva')) {
      return const ReservaDuplicadaFailure();
    }
    if (mensaje.contains('lista de espera está completa')) {
      return const ListaEsperaLlenaFailure();
    }
    if (e.code == 'P0002') {
      return const SinClasesFailure();
    }
    return const AutorizacionInsuficienteFailure();
  }
}
