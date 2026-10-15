// Pruebas unitarias de los flujos de autenticación (tarea 6.11).
//
// Verifican, sin red ni backend, tres comportamientos clave del
// Servicio_Autenticacion con dobles de prueba (fakes):
//
//   - Req 2.1: un inicio de sesión correcto establece la sesión del Usuario
//     (el `AuthNotifier` queda con el perfil autenticado y el flujo de sesión
//     emite un evento `signedIn` con sesión activa).
//   - Req 2.4: el cierre de sesión finaliza la sesión (el `AuthNotifier` vuelve
//     a `AsyncData(null)` y el flujo de sesión emite `signedOut` sin sesión).
//   - Req 1.7: al registrarse con una foto, esta se sube a Storage y su URL
//     pública se asocia al perfil (`foto_url`); si no se proporciona foto, no
//     se realiza ninguna subida ni actualización de `foto_url`.
//
// Convención del proyecto: se usan fakes manuales (sin librería de mocking) que
// sustituyen a Supabase. Los flujos de login/logout se prueban a nivel de
// provider con un `AuthRepository` falso inyectado mediante
// `authRepositoryProvider.overrideWithValue(...)`; la asociación de foto se
// prueba a nivel de repositorio (`AuthRepositoryImpl`) con fuentes de datos
// falsas que registran las llamadas.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:olympus/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:olympus/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:olympus/features/auth/domain/entities/app_user.dart';
import 'package:olympus/features/auth/domain/repositories/auth_repository.dart';
import 'package:olympus/features/auth/presentation/providers/auth_providers.dart';
import 'package:olympus/features/profile/data/datasources/profile_remote_datasource.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Utilidades compartidas
// ---------------------------------------------------------------------------

/// Perfil de dominio de ejemplo para las pruebas de sesión.
const _perfilEjemplo = Profile(
  id: 'u1',
  nombre: 'Ana',
  apellidos: 'García',
  email: 'ana@example.com',
  saldoClases: 10,
);

/// Construye un [User] mínimo de gotrue para componer una [Session].
User _fakeUser({String id = 'u1', String email = 'ana@example.com'}) {
  return User(
    id: id,
    appMetadata: const <String, dynamic>{},
    userMetadata: const <String, dynamic>{},
    aud: 'authenticated',
    email: email,
    createdAt: DateTime.utc(2025, 1, 1).toIso8601String(),
  );
}

/// Construye una [Session] activa mínima (sesión establecida).
Session _fakeSession({String id = 'u1', String email = 'ana@example.com'}) {
  return Session(
    accessToken: 'token-$id',
    tokenType: 'bearer',
    user: _fakeUser(id: id, email: email),
  );
}

// ---------------------------------------------------------------------------
// Fake de AuthRepository para las pruebas de login/logout a nivel de provider
// ---------------------------------------------------------------------------

/// `AuthRepository` falso que mantiene en memoria el estado de sesión y emite
/// los cambios por un `StreamController`, sin contactar con Supabase.
class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthState>.broadcast();

  /// Última sesión emitida (null = sin sesión). Refleja el estado de sesión.
  Session? sesionActual;

  int signInLlamadas = 0;
  int signOutLlamadas = 0;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    signInLlamadas++;
    // Un inicio de sesión correcto establece la sesión (Req 2.1).
    sesionActual = _fakeSession(email: email);
    _controller.add(AuthState(AuthChangeEvent.signedIn, sesionActual));
    return _perfilEjemplo.copyWith(email: email);
  }

  @override
  Future<void> signOut() async {
    signOutLlamadas++;
    // El cierre de sesión finaliza la sesión (Req 2.4).
    sesionActual = null;
    _controller.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Stream<AuthState> authStateChanges() => _controller.stream;

  @override
  Future<AppUser?> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
    XFile? foto,
  }) async {
    throw UnimplementedError('no usado en estas pruebas');
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    throw UnimplementedError('no usado en estas pruebas');
  }

  @override
  Future<void> updatePasswordWithToken(String newPassword) async {
    throw UnimplementedError('no usado en estas pruebas');
  }

  void dispose() => _controller.close();
}

// ---------------------------------------------------------------------------
// Fakes de las fuentes de datos para la prueba de asociación de foto (Req 1.7)
// ---------------------------------------------------------------------------

/// `AuthRemoteDataSource` falso: `signUp` devuelve una respuesta con sesión
/// activa (confirmación de email desactivada) para que el repositorio continúe
/// con la asociación de la foto.
class _FakeAuthDataSource extends AuthRemoteDataSource {
  _FakeAuthDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  @override
  Future<AuthResponse> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
  }) async {
    return AuthResponse(session: _fakeSession(email: email));
  }
}

/// `ProfileRemoteDataSource` falso que registra las llamadas relevantes para
/// comprobar la asociación de la foto al perfil (Req 1.7), sin tocar Storage ni
/// la base de datos.
class _FakeProfileDataSource extends ProfileRemoteDataSource {
  _FakeProfileDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  /// URL pública simulada que devuelve la "subida" del avatar.
  String urlPublicaSimulada = 'https://cdn.example.com/u1/avatar.jpg';

  int uploadAvatarLlamadas = 0;
  Uint8List? bytesSubidos;
  Map<String, dynamic>? cambiosActualizados;

  @override
  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String fileExtension,
    String? contentType,
  }) async {
    uploadAvatarLlamadas++;
    bytesSubidos = bytes;
    return urlPublicaSimulada;
  }

  @override
  Future<Map<String, dynamic>> updateMyProfile(
    Map<String, dynamic> cambios,
  ) async {
    cambiosActualizados = cambios;
    return _perfilRow();
  }

  @override
  Future<Map<String, dynamic>> fetchMyProfile() async => _perfilRow();

  Map<String, dynamic> _perfilRow() => <String, dynamic>{
    'id': 'u1',
    'nombre': 'Ana',
    'apellidos': 'García',
    'foto_url': cambiosActualizados?['foto_url'],
    'email': 'ana@example.com',
    'saldo_clases': 10,
    'estado': 'activo',
    'rol': 'usuario',
    'metadata': <String, dynamic>{},
    'created_at': '2025-01-01T00:00:00.000Z',
  };
}

/// `XFile` en memoria con bytes fijos para no depender del sistema de ficheros.
class _FakeXFile extends XFile {
  _FakeXFile(this._bytes, {String name = 'foto.png'})
    : super.fromData(_bytes, name: name, mimeType: 'image/png');

  final Uint8List _bytes;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

void main() {
  group('Flujos de autenticación (tarea 6.11)', () {
    group('Login/logout a nivel de provider', () {
      late _FakeAuthRepository fakeRepo;
      late ProviderContainer container;

      setUp(() {
        fakeRepo = _FakeAuthRepository();
        container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(fakeRepo)],
        );
      });

      tearDown(() {
        container.dispose();
        fakeRepo.dispose();
      });

      test(
        'el inicio de sesión correcto establece la sesión (Req 2.1)',
        () async {
          // Suscripción al flujo de sesión para capturar el evento emitido.
          final eventos = <AuthState>[];
          final sub = fakeRepo.authStateChanges().listen(eventos.add);
          addTearDown(sub.cancel);

          // Estado inicial: sin usuario autenticado por el notifier.
          final notifier = container.read(authNotifierProvider.notifier);
          await container.read(authNotifierProvider.future);
          expect(container.read(authNotifierProvider).value, isNull);
          expect(fakeRepo.sesionActual, isNull);

          await notifier.signIn(
            email: 'ana@example.com',
            password: 'password123',
          );

          // El repositorio recibió la orden de iniciar sesión.
          expect(fakeRepo.signInLlamadas, 1);

          // La sesión queda establecida (Req 2.1).
          expect(fakeRepo.sesionActual, isNotNull);
          expect(fakeRepo.sesionActual!.user.email, 'ana@example.com');

          // El notifier refleja el perfil autenticado (éxito, sin error).
          final estado = container.read(authNotifierProvider);
          expect(estado.hasError, isFalse);
          expect(estado.value, isNotNull);
          expect(estado.value!.email, 'ana@example.com');

          // El flujo de sesión emitió un evento de sesión iniciada.
          await Future<void>.delayed(Duration.zero);
          expect(eventos, isNotEmpty);
          expect(eventos.last.event, AuthChangeEvent.signedIn);
          expect(eventos.last.session, isNotNull);
        },
      );

      test('el cierre de sesión finaliza la sesión (Req 2.4)', () async {
        final eventos = <AuthState>[];
        final sub = fakeRepo.authStateChanges().listen(eventos.add);
        addTearDown(sub.cancel);

        final notifier = container.read(authNotifierProvider.notifier);
        await container.read(authNotifierProvider.future);

        // Primero se inicia sesión para tener una sesión activa que cerrar.
        await notifier.signIn(
          email: 'ana@example.com',
          password: 'password123',
        );
        expect(fakeRepo.sesionActual, isNotNull);

        await notifier.signOut();

        // El repositorio recibió la orden de cerrar sesión.
        expect(fakeRepo.signOutLlamadas, 1);

        // La sesión queda finalizada (Req 2.4).
        expect(fakeRepo.sesionActual, isNull);

        // El notifier vuelve a AsyncData(null): sin usuario autenticado.
        final estado = container.read(authNotifierProvider);
        expect(estado.hasError, isFalse);
        expect(estado.value, isNull);

        // El último evento del flujo de sesión es un cierre sin sesión.
        await Future<void>.delayed(Duration.zero);
        expect(eventos.last.event, AuthChangeEvent.signedOut);
        expect(eventos.last.session, isNull);
      });
    });

    group('Asociación de foto en el registro (Req 1.7)', () {
      late _FakeAuthDataSource fakeAuth;
      late _FakeProfileDataSource fakeProfiles;
      late AuthRepositoryImpl repo;

      setUp(() {
        fakeAuth = _FakeAuthDataSource();
        fakeProfiles = _FakeProfileDataSource();
        repo = AuthRepositoryImpl(
          authDataSource: fakeAuth,
          profileDataSource: fakeProfiles,
        );
      });

      test('al registrarse con foto, se sube a Storage y se asocia su URL al '
          'perfil (foto_url) (Req 1.7)', () async {
        final foto = _FakeXFile(Uint8List.fromList(<int>[1, 2, 3, 4]));

        final perfil = await repo.signUp(
          nombre: 'Ana',
          apellidos: 'García',
          email: 'ana@example.com',
          password: 'password123',
          foto: foto,
        );

        // La foto se subió a Storage (Req 1.7).
        expect(fakeProfiles.uploadAvatarLlamadas, 1);
        expect(fakeProfiles.bytesSubidos, Uint8List.fromList([1, 2, 3, 4]));

        // La URL pública resultante se asocia al perfil como `foto_url`.
        expect(fakeProfiles.cambiosActualizados, isNotNull);
        expect(
          fakeProfiles.cambiosActualizados!['foto_url'],
          fakeProfiles.urlPublicaSimulada,
        );

        // El perfil devuelto refleja la foto asociada.
        expect(perfil, isNotNull);
        expect(perfil!.fotoUrl, fakeProfiles.urlPublicaSimulada);
      });

      test('al registrarse sin foto, no se sube nada ni se actualiza foto_url '
          '(Req 1.7)', () async {
        final perfil = await repo.signUp(
          nombre: 'Ana',
          apellidos: 'García',
          email: 'ana@example.com',
          password: 'password123',
        );

        // Sin foto no hay subida a Storage ni actualización de foto_url.
        expect(fakeProfiles.uploadAvatarLlamadas, 0);
        expect(fakeProfiles.cambiosActualizados, isNull);

        // El perfil se crea igualmente, sin foto asociada.
        expect(perfil, isNotNull);
        expect(perfil!.fotoUrl, isNull);
      });
    });
  });
}
