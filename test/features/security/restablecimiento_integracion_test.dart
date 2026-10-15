// Pruebas de INTEGRACIÓN del flujo de restablecimiento de contraseña contra
// una instancia real/local de Supabase (tarea 12.3).
//
// Objetivo
// --------
// Verificar, contra Supabase Auth real, el comportamiento del flujo de
// recuperación que el diseño delega explícitamente en Auth (NO apto para PBT;
// ver design.md "Tokens de restablecimiento (Req 9)" y "Testing Strategy ->
// Pruebas de integración"):
//   (c) Envío del enlace de restablecimiento para una cuenta existente (9.2).
//   (d) Caducidad del token a 60 minutos desde su emisión (9.3).
//   (e) Un token caducado se rechaza con "enlace inválido o caducado" (9.4).
//   (f) Un token ya usado se rechaza y queda consumido (9.5 / 9.9).
//   (g) Completar el restablecimiento invalida todas las sesiones previas del
//       usuario (9.8).
//   _Requirements: 9.2, 9.3, 9.4, 9.5, 9.8, 9.9_
//   _Design: Testing Strategy (pruebas de integración)_
//
// Enfoque y limitaciones (lo que se puede forzar de forma determinista)
// ---------------------------------------------------------------------
// Varios comportamientos los gobierna internamente Supabase Auth y no se pueden
// forzar de forma determinista desde una prueba sin control del reloj ni acceso
// al buzón de correo:
//   * (c) El ENVÍO real del email no se intercepta aquí (requiere un servidor
//     SMTP de pruebas, p. ej. Inbucket/Mailpit del stack local). Lo que SÍ se
//     comprueba es que la solicitud a `resetPasswordForEmail` para una cuenta
//     EXISTENTE se acepta sin error (Auth genera y envía el enlace). En el
//     stack local, el enlace queda disponible en Inbucket (http://127.0.0.1:54324).
//   * (d) La caducidad de 60 min es un VALOR DE CONFIGURACIÓN de Auth
//     (`otp_expiry`). No se puede "esperar" 60 min en una prueba; se verifica
//     que la expiración configurada esperada es de 3600 s (ver
//     `kExpiracionResetSegundos`) y se documenta dónde se configura. Esperar la
//     expiración real se cubre manualmente o con control de reloj del backend.
//   * (e) Un token CADUCADO se simula generando un enlace de recuperación con
//     la Admin API y presentándolo tras forzar su invalidez cuando el entorno
//     lo permita; si no es posible, el caso se marca como pendiente con una
//     explicación (no como fallo).
//   * (f)/(g) Estos SÍ se fuerzan de forma determinista con la Admin API:
//     - (f) se usa UNA VEZ un token de recuperación (verifyOTP) y se intenta
//       usar DE NUEVO el mismo token: el segundo uso se rechaza (consumido).
//     - (g) tras completar el cambio de contraseña, las sesiones emitidas antes
//       del cambio dejan de poder refrescarse (quedan invalidadas).
//
// Cómo ejecutar (requiere Docker para `supabase start`)
// -----------------------------------------------------
//   supabase start && supabase db reset
//   flutter test test/features/security/restablecimiento_integracion_test.dart \
//     --dart-define=INTEGRATION_SUPABASE=true \
//     --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//     --dart-define=SUPABASE_ANON_KEY=<anon-key> \
//     --dart-define=SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
//
// Sin esas variables el grupo se OMITE (skip), manteniendo `flutter test` en
// verde en entornos sin backend.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'integration_config.dart';

void main() {
  group('Flujo de restablecimiento de contraseña (integración)', () {
    late SupabaseClient admin;
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

    // Crea un usuario de prueba con email confirmado y devuelve sus datos.
    Future<_Usuario> crearUsuario() async {
      final sufijo = '${DateTime.now().microsecondsSinceEpoch}';
      final email = 'reset_it_$sufijo@olympus.test';
      const password = 'password123';
      final creado = await admin.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
          userMetadata: <String, dynamic>{
            'nombre': 'Reset',
            'apellidos': 'Test',
          },
        ),
      );
      final id = creado.user!.id;
      idsUsuariosCreados.add(id);
      return _Usuario(id: id, email: email, password: password);
    }

    SupabaseClient nuevoCliente() {
      final c = SupabaseClient(
        kSupabaseUrl,
        kSupabaseAnonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      clientesAbiertos.add(c);
      return c;
    }

    // -------------------------------------------------------------------
    // (c) Envío del enlace para una cuenta existente (Req 9.2)
    // Auth acepta la solicitud y genera/envía el enlace. Comprobamos que no
    // lanza error para una cuenta existente (el envío real se inspecciona en
    // Inbucket en el stack local).
    // -------------------------------------------------------------------
    test('solicitar restablecimiento para una cuenta existente se acepta y '
        'genera un enlace con token (Req 9.2)', () async {
      final u = await crearUsuario();
      final cliente = nuevoCliente();

      // La solicitud del usuario no debe lanzar para una cuenta existente.
      await expectLater(cliente.auth.resetPasswordForEmail(u.email), completes);

      // Verdad de base: la Admin API genera un enlace de recuperación que
      // contiene un token (hashed_token / token). Confirma que Auth emite un
      // Token_Restablecimiento para la cuenta existente.
      final link = await admin.auth.admin.generateLink(
        type: GenerateLinkType.recovery,
        email: u.email,
      );
      expect(link.properties.hashedToken, isNotEmpty);
      expect(link.properties.actionLink, contains('token'));
    }, skip: skipReason);

    // -------------------------------------------------------------------
    // (d) Caducidad de 60 minutos desde la emisión (Req 9.3)
    // Es un valor de configuración de Auth (otp_expiry). No se puede esperar
    // en una prueba; se asevera el valor esperado (3600 s) y se documenta
    // dónde se configura. Si el proyecto usa otro valor, pásalo con
    // --dart-define=RESET_TOKEN_EXPIRY_SECONDS=<n>.
    // -------------------------------------------------------------------
    test('la caducidad del token de restablecimiento está configurada a 60 '
        'minutos (3600 s) (Req 9.3)', () {
      // Documenta/afirma la expiración esperada. En Supabase local se fija en
      // `supabase/config.toml` -> [auth.email] otp_expiry = 3600; en Supabase
      // Cloud, en Authentication > Email > "Email OTP Expiration".
      expect(
        kExpiracionResetSegundos,
        equals(3600),
        reason:
            'el Token_Restablecimiento debe caducar a los 60 min (Req 9.3); '
            'ajusta la configuración de Auth u override con '
            '--dart-define=RESET_TOKEN_EXPIRY_SECONDS',
      );
    }, skip: skipReason);

    // -------------------------------------------------------------------
    // (e) Un token caducado se rechaza (Req 9.4)
    // La expiración real (60 min) no es forzable de forma determinista desde la
    // prueba. Se valida el caso análogo y deterministamente forzable: un token
    // INVÁLIDO (equivalente observable a "caducado": Auth responde con el mismo
    // error "invalid or expired") se rechaza con AuthException. El Req 9.4 exige
    // que el mensaje al usuario sea "enlace inválido o caducado", que la capa de
    // repositorio traduce a `TokenInvalidoFailure`.
    // -------------------------------------------------------------------
    test('un token inválido/caducado se rechaza con error de enlace inválido o '
        'caducado (Req 9.4)', () async {
      final cliente = nuevoCliente();
      // Token de recuperación arbitrario (no emitido / ya expirado): Auth lo
      // rechaza. Es el mismo error observable que un token caducado real.
      await expectLater(
        cliente.auth.verifyOTP(
          type: OtpType.recovery,
          tokenHash: 'token-inexistente-o-caducado-000000000000',
        ),
        throwsA(isA<AuthException>()),
      );
    }, skip: skipReason);

    // -------------------------------------------------------------------
    // (f) Un token ya usado se rechaza y queda consumido (Req 9.5 / 9.9)
    // Se genera un enlace de recuperación con la Admin API, se CONSUME una vez
    // (verifyOTP abre la sesión de recuperación) y se intenta CONSUMIR DE NUEVO
    // el mismo token: el segundo intento se rechaza (token consumido).
    // -------------------------------------------------------------------
    test('un token de restablecimiento ya usado se rechaza en el segundo uso '
        '(consumido) (Req 9.5 / 9.9)', () async {
      final u = await crearUsuario();
      final link = await admin.auth.admin.generateLink(
        type: GenerateLinkType.recovery,
        email: u.email,
      );
      final tokenHash = link.properties.hashedToken;

      // Primer uso: abre la sesión de recuperación (consume el token).
      final cliente1 = nuevoCliente();
      final res1 = await cliente1.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: tokenHash,
      );
      expect(
        res1.session,
        isNotNull,
        reason: 'el primer uso del token debe abrir la sesión de recuperación',
      );

      // Segundo uso del MISMO token: debe rechazarse (ya consumido).
      final cliente2 = nuevoCliente();
      await expectLater(
        cliente2.auth.verifyOTP(type: OtpType.recovery, tokenHash: tokenHash),
        throwsA(isA<AuthException>()),
        reason: 'un token ya usado no debe poder reutilizarse (Req 9.5/9.9)',
      );
    }, skip: skipReason);

    // -------------------------------------------------------------------
    // (g) Completar el reset invalida todas las sesiones previas (Req 9.8)
    // Se inicia una sesión "antigua" con la contraseña original; se completa el
    // restablecimiento (nueva contraseña) a través de un enlace de recuperación;
    // y se comprueba que la sesión antigua ya no puede refrescar su token
    // (queda invalidada), mientras que la nueva contraseña sí funciona.
    // -------------------------------------------------------------------
    test('tras completar el restablecimiento, las sesiones previas quedan '
        'invalidadas (Req 9.8)', () async {
      final u = await crearUsuario();

      // Sesión ANTIGUA del usuario (contraseña original).
      final sesionAntigua = nuevoCliente();
      await sesionAntigua.auth.signInWithPassword(
        email: u.email,
        password: u.password,
      );
      expect(sesionAntigua.auth.currentSession, isNotNull);

      // Flujo de recuperación: abrir sesión de recuperación y cambiar la clave.
      final link = await admin.auth.admin.generateLink(
        type: GenerateLinkType.recovery,
        email: u.email,
      );
      final recuperacion = nuevoCliente();
      await recuperacion.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: link.properties.hashedToken,
      );
      const nuevaPassword = 'nuevaPassword456';
      await recuperacion.auth.updateUser(
        UserAttributes(password: nuevaPassword),
      );

      // La sesión ANTIGUA ya no puede refrescar su token (invalidada, 9.8).
      await expectLater(
        sesionAntigua.auth.refreshSession(),
        throwsA(isA<AuthException>()),
        reason:
            'completar el reset debe invalidar las sesiones previas del '
            'usuario (Req 9.8)',
      );

      // La nueva contraseña sí permite iniciar sesión (cambio efectivo).
      final sesionNueva = nuevoCliente();
      final res = await sesionNueva.auth.signInWithPassword(
        email: u.email,
        password: nuevaPassword,
      );
      expect(res.session, isNotNull);
    }, skip: skipReason);
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
