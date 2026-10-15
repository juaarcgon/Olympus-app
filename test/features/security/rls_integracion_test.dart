// Pruebas de INTEGRACIÓN de las políticas RLS de `profiles` contra una
// instancia real/local de Supabase (tarea 12.3).
//
// Objetivo
// --------
// Reforzar en la base de datos real las propiedades 19 y 20 (verificadas como
// funciones puras en `usuario_solo_accede_a_sus_datos_test.dart` y
// `sin_sesion_sin_acceso_datos_test.dart`): comprobar que la política RLS de
// SELECT sobre `profiles`
//   USING (auth.uid() = id OR es_superadmin())
// (migración `supabase/migrations/0003_rls.sql`) deniega de verdad:
//   (a) el acceso ANÓNIMO (sin JWT, rol `anon`): ninguna fila (Req 7.3), y
//   (b) el acceso CRUZADO (un usuario estándar leyendo el perfil de otro):
//       ninguna fila; a la vez permite leer el perfil PROPIO y, para un
//       superadministrador, el de cualquier usuario (Req 7.2).
//   _Requirements: 7.2, 7.3_
//   _Design: Testing Strategy (pruebas de integración); Security and RLS Strategy_
//
// A diferencia del grueso de la suite (fakes en memoria, sin red), estas
// pruebas necesitan una INSTANCIA REAL de Supabase (preferiblemente local) con
// las migraciones aplicadas. Para no romper `flutter test` en entornos sin
// backend, el grupo entero se OMITE automáticamente salvo que se proporcionen
// las variables de conexión en tiempo de compilación (ver README de la carpeta
// y la cabecera de `reservas_rpc_integracion_test.dart`).
//
// Cómo ejecutar (requiere Docker para `supabase start`)
// -----------------------------------------------------
//   1. Levantar Supabase local y aplicar las migraciones de `supabase/`:
//        supabase start
//        supabase db reset          # aplica supabase/migrations/*.sql
//   2. Anotar la API URL, la anon key y la SERVICE ROLE key de `supabase status`.
//   3. Ejecutar SOLO estas pruebas pasando las variables:
//        flutter test test/features/security/rls_integracion_test.dart \
//          --dart-define=INTEGRATION_SUPABASE=true \
//          --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//          --dart-define=SUPABASE_ANON_KEY=<anon-key> \
//          --dart-define=SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
//
// Sin `INTEGRATION_SUPABASE=true` (o sin las claves) el grupo se marca como
// `skip`, de modo que `flutter test` sigue en verde en CI/entornos sin
// Supabase. El código se compila y analiza igualmente (`flutter analyze`).

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'integration_config.dart';

void main() {
  group('RLS de profiles: acceso anónimo y cruzado denegado (integración)', () {
    // Cliente con service role: prepara datos y lee sin RLS (verdad de base).
    late SupabaseClient admin;

    // Ids de usuarios creados, para su limpieza posterior.
    final idsUsuariosCreados = <String>[];
    final clientesAbiertos = <SupabaseClient>[];

    setUpAll(() {
      if (!integracionDisponible) return;
      admin = SupabaseClient(
        kSupabaseUrl,
        kSupabaseServiceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });

    tearDownAll(() async {
      if (!integracionDisponible) return;
      for (final id in idsUsuariosCreados) {
        try {
          await admin.auth.admin.deleteUser(id);
        } catch (_) {
          // Limpieza best-effort.
        }
      }
      idsUsuariosCreados.clear();
      for (final c in clientesAbiertos) {
        try {
          await c.dispose();
        } catch (_) {
          // Ignorado.
        }
      }
      clientesAbiertos.clear();
      await admin.dispose();
    });

    // Crea un usuario de prueba (email confirmado) con el rol indicado y
    // devuelve su id, email y contraseña. El trigger `on_auth_user_created`
    // crea su `profiles`; si [superadmin] es true, se promociona con service
    // role (saltando el trigger de inmutabilidad).
    Future<_Usuario> crearUsuario({bool superadmin = false}) async {
      final sufijo = '${DateTime.now().microsecondsSinceEpoch}';
      final email = 'rls_it_$sufijo@olympus.test';
      const password = 'password123';
      final creado = await admin.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
          userMetadata: <String, dynamic>{'nombre': 'RLS', 'apellidos': 'Test'},
        ),
      );
      final id = creado.user!.id;
      idsUsuariosCreados.add(id);
      if (superadmin) {
        await admin
            .from('profiles')
            .update(<String, dynamic>{'rol': 'superadmin'})
            .eq('id', id);
      }
      return _Usuario(id: id, email: email, password: password);
    }

    // Abre un cliente autenticado como el usuario dado (su propio JWT).
    Future<SupabaseClient> clienteDe(_Usuario u) async {
      final client = SupabaseClient(
        kSupabaseUrl,
        kSupabaseAnonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.signInWithPassword(
        email: u.email,
        password: u.password,
      );
      clientesAbiertos.add(client);
      return client;
    }

    // -------------------------------------------------------------------
    // (a) Acceso ANÓNIMO denegado: sin sesión, SELECT no devuelve filas
    //     (Property 20 / Req 7.3). El rol `anon` no tiene ninguna política,
    //     por lo que RLS devuelve conjunto vacío (no error).
    // -------------------------------------------------------------------
    test(
      'cliente anónimo (sin JWT) no obtiene ninguna fila de profiles (Req 7.3)',
      () async {
        // Un perfil real existe en la base (creado con service role)...
        final objetivo = await crearUsuario();

        // ...pero un cliente anónimo (rol `anon`, sin sesión) no lo ve.
        final anon = SupabaseClient(
          kSupabaseUrl,
          kSupabaseAnonKey,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        clientesAbiertos.add(anon);

        final filas = await anon.from('profiles').select('id');
        expect(
          filas,
          isEmpty,
          reason: 'sin sesión activa RLS no debe devolver ninguna fila',
        );

        // Ni siquiera filtrando explícitamente por el id existente.
        final filasPorId = await anon
            .from('profiles')
            .select('id')
            .eq('id', objetivo.id);
        expect(filasPorId, isEmpty);
      },
      skip: skipReason,
    );

    // -------------------------------------------------------------------
    // (b1) Acceso CRUZADO denegado: un usuario estándar no ve el perfil de
    //      otro (Property 19 / Req 7.2).
    // -------------------------------------------------------------------
    test(
      'usuario estándar no ve el perfil de otro usuario (Req 7.2)',
      () async {
        final a = await crearUsuario();
        final b = await crearUsuario();
        final clienteA = await clienteDe(a);

        // A intenta leer explícitamente la fila de B: RLS la oculta.
        final filasB = await clienteA
            .from('profiles')
            .select('id')
            .eq('id', b.id);
        expect(
          filasB,
          isEmpty,
          reason: 'un usuario estándar no debe ver el perfil de otro',
        );

        // Un SELECT sin filtro solo devuelve su PROPIA fila (no la de B).
        final todas = await clienteA.from('profiles').select('id');
        final ids = (todas as List)
            .map((r) => (r as Map)['id'] as String)
            .toList();
        expect(ids, equals(<String>[a.id]));
        expect(ids, isNot(contains(b.id)));
      },
      skip: skipReason,
    );

    // -------------------------------------------------------------------
    // (b2) Acceso PROPIO permitido: la rama `auth.uid() = id` de la política.
    // -------------------------------------------------------------------
    test(
      'usuario estándar sí ve su propio perfil (rama auth.uid() = id, Req 7.2)',
      () async {
        final a = await crearUsuario();
        final clienteA = await clienteDe(a);

        final propio = await clienteA
            .from('profiles')
            .select('id')
            .eq('id', a.id);
        final ids = (propio as List)
            .map((r) => (r as Map)['id'] as String)
            .toList();
        expect(ids, equals(<String>[a.id]));
      },
      skip: skipReason,
    );

    // -------------------------------------------------------------------
    // (b3) Acceso de SUPERADMIN permitido: la rama `es_superadmin()` de la
    //      política le deja ver el perfil de cualquier usuario (Req 7.2).
    // -------------------------------------------------------------------
    test(
      'un superadministrador ve el perfil de cualquier usuario (Req 7.2)',
      () async {
        final admdel = await crearUsuario(superadmin: true);
        final otro = await crearUsuario();
        final clienteAdmin = await clienteDe(admdel);

        // El superadmin ve la fila de `otro`...
        final filasOtro = await clienteAdmin
            .from('profiles')
            .select('id')
            .eq('id', otro.id);
        final idsOtro = (filasOtro as List)
            .map((r) => (r as Map)['id'] as String)
            .toList();
        expect(idsOtro, equals(<String>[otro.id]));

        // ...y, sin filtro, ve al menos ambos perfiles (el suyo y el de `otro`).
        final todas = await clienteAdmin.from('profiles').select('id');
        final ids = (todas as List)
            .map((r) => (r as Map)['id'] as String)
            .toSet();
        expect(ids, containsAll(<String>[admdel.id, otro.id]));
      },
      skip: skipReason,
    );
  });
}

/// Usuario de prueba creado en Supabase Auth.
class _Usuario {
  const _Usuario({
    required this.id,
    required this.email,
    required this.password,
  });

  final String id;
  final String email;
  final String password;
}
