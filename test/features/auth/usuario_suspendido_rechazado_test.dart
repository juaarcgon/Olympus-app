// Prueba de propiedad del rechazo del usuario suspendido.
//
// Feature: gym-management-app, Property 7
//
// Property 7: El usuario suspendido no puede iniciar sesión ni restablecer su
// contraseña.
// "Para cualquier usuario con estado == 'suspendido', tanto el inicio de sesión
//  como el restablecimiento de contraseña se rechazan con un mensaje de cuenta
//  suspendida."
//
// Validates: Requirements 2.3, 9.10
//
// La propiedad se verifica contra el seam real del Servicio_Autenticacion
// (`AuthRepositoryImpl.signIn` y `AuthRepositoryImpl.updatePasswordWithToken`),
// inyectando fakes (sin red ni backend) de la `AuthRemoteDataSource` (Supabase
// Auth) y de la `ProfileRemoteDataSource` (fila de `profiles`). Los fakes de
// Auth aceptan las credenciales/actualización (como haría Supabase para una
// cuenta cuyas credenciales son correctas), y el fake de perfil devuelve una
// fila con el `estado` generado. Así se ejercita exactamente la comprobación
// defensiva del repositorio: si el perfil está suspendido, cierra la sesión y
// lanza `CuentaSuspendidaFailure` (Req 2.3 en login, Req 9.10 en
// restablecimiento); si está activo, la operación procede sin ese fallo.
//
// Se usa `glados` con un mínimo de 100 iteraciones, generando el estado del
// usuario (activo/suspendido) junto con email y contraseña arbitrarios, y se
// comprueba que:
//   - estado == suspendido  -> signIn y updatePasswordWithToken lanzan
//     CuentaSuspendidaFailure y, además, se cierra la sesión (no queda sesión
//     colgada),
//   - estado == activo      -> ninguna de las dos operaciones lanza
//     CuentaSuspendidaFailure.

// `glados` reexporta el paquete `test`; esta prueba necesita además los tipos
// de Supabase para construir los fakes de los data sources. Para evitar la
// colisión del símbolo `test` entre `glados` y `flutter_test`, se usa
// únicamente la API de `glados` (que ya aporta `expect`, `group`, `test` y los
// matchers).
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:olympus/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:olympus/features/profile/data/datasources/profile_remote_datasource.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `AuthRemoteDataSource` falso que simula un backend de Auth en el que las
/// credenciales son correctas: `signInWithPassword` y `updatePassword`
/// completan con éxito. Registra si se solicitó el cierre de sesión, para
/// comprobar que una cuenta suspendida no deja la sesión colgada.
class _FakeAuthDataSource extends AuthRemoteDataSource {
  _FakeAuthDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  /// Número de veces que el repositorio solicitó cerrar la sesión.
  int signOutCount = 0;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    // Credenciales correctas: Auth no lanza. El veredicto de suspensión lo
    // decide el repositorio tras leer el perfil.
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<UserResponse> updatePassword(String newPassword) async {
    // La actualización dentro de la sesión de recuperación tiene éxito en Auth.
    return UserResponse.fromJson(const <String, dynamic>{});
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
  }
}

/// `ProfileRemoteDataSource` falso que devuelve una fila de `profiles` con el
/// [estado] indicado, sin contactar con Supabase. Es el espejo de la lectura
/// que el repositorio hace tras autenticar para comprobar la suspensión.
class _FakeProfileDataSource extends ProfileRemoteDataSource {
  _FakeProfileDataSource(this.estado)
    : super(client: SupabaseClient('http://localhost', 'anon'));

  /// Estado persistido del usuario ('activo' o 'suspendido').
  final EstadoUsuario estado;

  @override
  Future<Map<String, dynamic>> fetchMyProfile() async {
    return <String, dynamic>{
      'id': 'id-usuario',
      'nombre': 'Nombre',
      'apellidos': 'Apellidos',
      'foto_url': null,
      'email': 'usuario@example.com',
      'saldo_clases': 10,
      'estado': estado.valor,
      'rol': RolUsuario.usuario.valor,
      'metadata': <String, dynamic>{},
      'created_at': null,
    };
  }
}

/// Construye un repositorio cuyo perfil tiene el [estado] indicado, con fakes
/// que simulan credenciales correctas en Auth.
({AuthRepositoryImpl repo, _FakeAuthDataSource auth}) _repoConEstado(
  EstadoUsuario estado,
) {
  final auth = _FakeAuthDataSource();
  final repo = AuthRepositoryImpl(
    authDataSource: auth,
    profileDataSource: _FakeProfileDataSource(estado),
  );
  return (repo: repo, auth: auth);
}

/// Captura la excepción lanzada por [accion], o `null` si completa con éxito.
Future<Object?> _errorDe(Future<void> Function() accion) async {
  try {
    await accion();
    return null;
  } on Object catch (e) {
    return e;
  }
}

/// Generador del estado del usuario (activo/suspendido) de forma uniforme.
Generator<EstadoUsuario> get _anyEstado => any.positiveIntOrZero.map(
  (n) => EstadoUsuario.values[n % EstadoUsuario.values.length],
);

/// Generador de un email arbitrario con forma plausible.
Generator<String> get _anyEmail => any.combine2(
  any.nonEmptyLetterOrDigits,
  any.nonEmptyLetterOrDigits,
  (local, dominio) => '$local@$dominio.com',
);

/// Generador de una contraseña arbitraria de longitud válida (>= 8), para que
/// el guard de longitud no interfiera con la comprobación de suspensión en el
/// restablecimiento. Se parte de una cadena arbitraria no vacía y, si es más
/// corta de ocho (8) caracteres, se repite y recorta hasta alcanzar el mínimo.
Generator<String> get _anyPasswordValida => any.nonEmptyLetterOrDigits.map((s) {
  if (s.length >= 8) return s;
  final repetido = s * (8 ~/ s.length + 1);
  return repetido.substring(0, 8);
});

void main() {
  group('Feature: gym-management-app, Property 7 - el usuario suspendido no '
      'inicia sesión ni restablece contraseña', () {
    Glados3(_anyEstado, _anyEmail, _anyPasswordValida).test(
      'para cualquier usuario, el inicio de sesión se rechaza con '
      'CuentaSuspendidaFailure si y solo si está suspendido, cerrando la '
      'sesión (Req 2.3)',
      (estado, email, password) async {
        final creado = _repoConEstado(estado);

        final error = await _errorDe(
          () => creado.repo.signIn(email: email, password: password),
        );

        if (estado == EstadoUsuario.suspendido) {
          // Req 2.3: el inicio de sesión del usuario suspendido se rechaza con
          // un error de cuenta suspendida...
          expect(
            error,
            isA<CuentaSuspendidaFailure>(),
            reason:
                'un usuario suspendido no debe poder iniciar sesión '
                '(estado=$estado)',
          );
          // ...y no debe quedar una sesión activa colgada.
          expect(
            creado.auth.signOutCount,
            greaterThanOrEqualTo(1),
            reason: 'tras detectar la suspensión debe cerrarse la sesión',
          );
        } else {
          // Un usuario activo no se rechaza por suspensión.
          expect(
            error,
            isNot(isA<CuentaSuspendidaFailure>()),
            reason:
                'un usuario activo no debe recibir CuentaSuspendidaFailure '
                '(estado=$estado)',
          );
        }
      },
    );

    Glados3(_anyEstado, _anyEmail, _anyPasswordValida).test(
      'para cualquier usuario, el restablecimiento de contraseña se rechaza '
      'con CuentaSuspendidaFailure si y solo si está suspendido, cerrando la '
      'sesión (Req 9.10)',
      (estado, email, password) async {
        final creado = _repoConEstado(estado);

        final error = await _errorDe(
          () => creado.repo.updatePasswordWithToken(password),
        );

        if (estado == EstadoUsuario.suspendido) {
          // Req 9.10: el usuario suspendido no puede completar el
          // restablecimiento de su contraseña.
          expect(
            error,
            isA<CuentaSuspendidaFailure>(),
            reason:
                'un usuario suspendido no debe poder restablecer su '
                'contraseña (estado=$estado)',
          );
          expect(
            creado.auth.signOutCount,
            greaterThanOrEqualTo(1),
            reason: 'tras detectar la suspensión debe cerrarse la sesión',
          );
        } else {
          expect(
            error,
            isNot(isA<CuentaSuspendidaFailure>()),
            reason:
                'un usuario activo no debe recibir CuentaSuspendidaFailure '
                '(estado=$estado)',
          );
        }
      },
    );

    // Caso borde explícito: un usuario suspendido es rechazado en AMBAS
    // operaciones con el mismo tipo de fallo (lectura directa del Req 2.3/9.10).
    test(
      'un usuario suspendido es rechazado tanto en login como en '
      'restablecimiento con CuentaSuspendidaFailure (Req 2.3, 9.10)',
      () async {
        final login = _repoConEstado(EstadoUsuario.suspendido);
        final errorLogin = await _errorDe(
          () =>
              login.repo.signIn(email: 'ana@example.com', password: '12345678'),
        );
        expect(errorLogin, isA<CuentaSuspendidaFailure>());

        final reset = _repoConEstado(EstadoUsuario.suspendido);
        final errorReset = await _errorDe(
          () => reset.repo.updatePasswordWithToken('12345678'),
        );
        expect(errorReset, isA<CuentaSuspendidaFailure>());
      },
    );
  });
}
