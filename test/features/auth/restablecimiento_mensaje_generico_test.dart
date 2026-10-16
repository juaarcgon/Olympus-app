// Prueba de propiedad del mensaje genérico de restablecimiento de contraseña.
//
// Feature: gym-management-app, Property 29
//
// Property 29: La solicitud de restablecimiento devuelve siempre un mensaje
// genérico.
// "Para cualquier email (exista o no una cuenta asociada), la respuesta a una
//  solicitud de restablecimiento de contraseña es el mismo mensaje genérico,
//  sin revelar si el email corresponde a una cuenta."
//
// Validates: Requirements 9.1
//
// La propiedad se verifica contra el seam real del Servicio_Autenticacion
// (`AuthRepositoryImpl.requestPasswordReset`), inyectando una
// `AuthRemoteDataSource` falsa (sin red ni backend) que simula los distintos
// "mundos" posibles para un mismo email:
//   - el email SÍ está asociado a una cuenta -> el SDK responde con éxito,
//   - el email NO está asociado a una cuenta -> el SDK lanza `AuthException`,
//   - fallo técnico del proveedor -> se lanza una excepción arbitraria.
//
// El Req 9.1 exige que la respuesta observable por el Usuario sea SIEMPRE el
// mismo mensaje genérico, con independencia de cuál de esos mundos ocurra: la
// operación nunca debe propagar un error (lo que delataría la existencia o no
// de la cuenta) y la UI siempre muestra el mismo texto. Modelamos esa respuesta
// observable con [respuestaRestablecimiento], que invoca el repositorio y, si
// completa sin excepción, devuelve el mensaje genérico (espejo de lo que hace
// `ForgotPasswordScreen` tras `requestPasswordReset`). La propiedad comprueba
// que, para cualquier email y cualquier mundo, esa respuesta es idéntica a la
// de un email de control, de modo que un observador no puede distinguir si el
// email existe. Se usa `glados` con un mínimo de 100 iteraciones.

// `glados` reexporta el paquete `test`; aun así, esta prueba necesita los
// fakes de Supabase, por lo que importa también sus tipos. Para evitar la
// colisión del símbolo `test` entre `glados` y `flutter_test`, se usa
// únicamente la API de `glados` (que ya aporta `expect`, `group`, `test` y los
// matchers) y se oculta `test` del resto de imports donde haga falta.
import 'package:glados/glados.dart';
import 'package:olympus/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:olympus/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:olympus/features/profile/data/datasources/profile_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensaje genérico que la UI muestra tras solicitar el restablecimiento
/// (espejo del `_mensajeGenerico` de `ForgotPasswordScreen`, Req 9.1).
const String kMensajeGenerico =
    'Si el correo electrónico existe, se ha enviado un enlace de '
    'restablecimiento.';

/// Mundos posibles para un email dado al solicitar el restablecimiento.
enum MundoEmail {
  /// El email SÍ está asociado a una cuenta: el SDK responde con éxito.
  cuentaExiste,

  /// El email NO está asociado a una cuenta: el SDK lanza `AuthException`.
  cuentaNoExiste,

  /// Fallo técnico del proveedor: se lanza una excepción arbitraria.
  falloTecnico,
}

/// `AuthRemoteDataSource` falso que, en `resetPasswordForEmail`, reproduce el
/// comportamiento del [mundo] indicado para cada email, sin contactar con
/// Supabase.
class _FakeAuthDataSource extends AuthRemoteDataSource {
  _FakeAuthDataSource(this.mundo)
    : super(client: SupabaseClient('http://localhost', 'anon'));

  /// Mundo a simular para la próxima llamada a `resetPasswordForEmail`.
  final MundoEmail mundo;

  /// Emails para los que se solicitó el restablecimiento (para comprobar que
  /// el repositorio siempre delega la llamada, independientemente del mundo).
  final List<String> emailsSolicitados = <String>[];

  @override
  Future<void> resetPasswordForEmail(String email, {String? redirectTo}) async {
    emailsSolicitados.add(email);
    switch (mundo) {
      case MundoEmail.cuentaExiste:
        // El SDK acepta la solicitud (la cuenta existe): respuesta con éxito.
        return;
      case MundoEmail.cuentaNoExiste:
        // El SDK señala que no hay cuenta con ese email. Si el repositorio
        // propagara esto, se revelaría que el email no existe (viola Req 9.1).
        throw const AuthException(
          'User not found',
          code: 'user_not_found',
          statusCode: '404',
        );
      case MundoEmail.falloTecnico:
        // Fallo técnico arbitrario del proveedor (p. ej. caída de red). No debe
        // alterar la respuesta observable (Req 9.1).
        throw StateError('fallo técnico simulado del proveedor');
    }
  }
}

/// `ProfileRemoteDataSource` falso e inerte. `requestPasswordReset` nunca lo
/// usa, pero se inyecta para no construir el data source real (que exigiría
/// `Supabase.instance` inicializado). Cualquier uso inesperado falla ruidoso.
class _FakeProfileDataSource extends ProfileRemoteDataSource {
  _FakeProfileDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));
}

/// Respuesta observable por el Usuario a una solicitud de restablecimiento.
///
/// Invoca `AuthRepositoryImpl.requestPasswordReset` sobre el [mundo] indicado y
/// devuelve el [kMensajeGenerico] si la operación completa SIN excepción
/// (espejo de lo que hace `ForgotPasswordScreen`: tras volver la llamada,
/// siempre muestra el mensaje genérico). Si el repositorio propagara un error,
/// la excepción se propagaría aquí y la respuesta observable cambiaría, lo que
/// delataría información sobre la existencia del email (y la prueba fallaría).
Future<String> respuestaRestablecimiento(String email, MundoEmail mundo) async {
  // El `profileDataSource` no se usa en `requestPasswordReset`; se inyecta un
  // doble inerte para evitar depender de `Supabase.instance`.
  final repo = AuthRepositoryImpl(
    authDataSource: _FakeAuthDataSource(mundo),
    profileDataSource: _FakeProfileDataSource(),
  );
  await repo.requestPasswordReset(email);
  // Si llegamos aquí, la operación no reveló nada: la UI muestra el genérico.
  return kMensajeGenerico;
}

/// Generador de emails arbitrarios (incluye vacíos, con espacios y variados).
Generator<String> get _anyEmail => any.oneOf([
  // Emails con forma válida pero contenido arbitrario (existan o no).
  any.combine2(
    any.nonEmptyLetterOrDigits,
    any.nonEmptyLetterOrDigits,
    (local, dominio) => '$local@$dominio.com',
  ),
  // Cadenas arbitrarias cualesquiera (el Req 9.1 no exige validez de formato).
  any.letterOrDigits,
  // Variantes con espacios alrededor (el repositorio aplica trim).
  any.nonEmptyLetterOrDigits.map((s) => '  $s@example.com  '),
]);

/// Generador del mundo a simular para cada email (uniforme sobre los 3 mundos).
Generator<MundoEmail> get _anyMundo => any.positiveIntOrZero.map(
  (n) => MundoEmail.values[n % MundoEmail.values.length],
);

void main() {
  group('Feature: gym-management-app, Property 29 - la solicitud de '
      'restablecimiento devuelve siempre un mensaje genérico', () {
    Glados2(_anyEmail, _anyMundo).test(
      'para cualquier email y en cualquier mundo (la cuenta exista, no exista '
      'o haya un fallo técnico), la respuesta es siempre el mismo mensaje '
      'genérico y nunca revela si el email corresponde a una cuenta (Req 9.1)',
      (email, mundo) async {
        // Respuesta observable para este email en el mundo generado.
        final respuesta = await respuestaRestablecimiento(email, mundo);

        // 1) La respuesta es exactamente el mensaje genérico: la operación
        //    completó sin propagar error, con independencia del mundo.
        expect(
          respuesta,
          equals(kMensajeGenerico),
          reason:
              'la solicitud para "$email" en el mundo $mundo debe devolver '
              'el mensaje genérico sin propagar errores',
        );

        // 2) Indistinguibilidad: la respuesta es idéntica a la que se obtiene
        //    para un email de CONTROL cuya cuenta SÍ existe. Así un observador
        //    no puede distinguir el mundo real del email a partir de la
        //    respuesta (no se revela si el email corresponde a una cuenta).
        final respuestaControl = await respuestaRestablecimiento(
          'control@example.com',
          MundoEmail.cuentaExiste,
        );
        expect(
          respuesta,
          equals(respuestaControl),
          reason:
              'la respuesta no debe depender de si "$email" existe (mundo '
              '$mundo): debe ser idéntica a la de un email que sí existe',
        );
      },
    );

    // Caso borde explícito: para un MISMO email, los tres mundos producen la
    // misma respuesta observable. Es la lectura más directa de "no revela si
    // el email corresponde a una cuenta" (Req 9.1).
    test('para un mismo email, cuenta-existe, cuenta-no-existe y fallo-técnico '
        'devuelven la misma respuesta (Req 9.1)', () async {
      const email = 'ana@example.com';

      final existe = await respuestaRestablecimiento(
        email,
        MundoEmail.cuentaExiste,
      );
      final noExiste = await respuestaRestablecimiento(
        email,
        MundoEmail.cuentaNoExiste,
      );
      final falloTecnico = await respuestaRestablecimiento(
        email,
        MundoEmail.falloTecnico,
      );

      expect(existe, equals(kMensajeGenerico));
      expect(noExiste, equals(existe));
      expect(falloTecnico, equals(existe));
    });
  });
}
