// Implementación del Servicio_Autenticacion (AuthRepository) sobre Supabase.
//
// Orquesta la [AuthRemoteDataSource] (Supabase Auth), valida las entradas en el
// cliente y traduce las excepciones del SDK a `Failure` de dominio tipados,
// acorde a la estrategia de "Error Handling" del diseño. Para componer el
// perfil autenticado reutiliza la [ProfileRemoteDataSource] (lectura de la fila
// de `profiles` y subida de la foto al bucket `avatars`).
//
// Trazabilidad de requisitos:
// - Req 1.4: email duplicado -> `EmailEnUsoFailure` (delegado a Auth).
// - Req 1.5: formato de email -> `FormatoEmailFailure` (validado antes de Auth).
// - Req 1.6/9.6: longitud de contraseña -> `PasswordCortaFailure`.
// - Req 1.7: subida de la foto a Storage y asociación de `foto_url`.
// - Req 2.2: credenciales inválidas -> `CredencialesInvalidasFailure`.
// - Req 2.3/9.10: cuenta suspendida -> `CuentaSuspendidaFailure`.
// - Req 9.1: recuperación con respuesta genérica (no revela si el email existe).
// - Req 9.4/9.5: token caducado/usado -> `TokenInvalidoFailure`.
//
// Ref. diseño: "Servicio_Autenticacion"; "Error Handling"; "Supabase Storage".

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../profile/data/datasources/profile_remote_datasource.dart';
import '../../../profile/domain/entities/profile.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

/// Implementación de [AuthRepository] respaldada por Supabase Auth.
class AuthRepositoryImpl implements AuthRepository {
  /// Crea el repositorio con sus fuentes de datos.
  ///
  /// Si no se proporcionan, se construyen sobre la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  AuthRepositoryImpl({
    AuthRemoteDataSource? authDataSource,
    ProfileRemoteDataSource? profileDataSource,
  }) : _auth = authDataSource ?? AuthRemoteDataSource(),
       _profiles = profileDataSource ?? ProfileRemoteDataSource();

  final AuthRemoteDataSource _auth;
  final ProfileRemoteDataSource _profiles;

  @override
  Future<AppUser?> signUp({
    required String nombre,
    required String apellidos,
    required String email,
    required String password,
    XFile? foto,
  }) async {
    // Validación en el cliente ANTES de llamar a Auth (Req 1.5, 1.6).
    final emailFailure = validarEmail(email);
    if (emailFailure != null) throw emailFailure;
    final passwordFailure = validarPassword(password);
    if (passwordFailure != null) throw passwordFailure;

    try {
      // El hashing y el control de email duplicado los gestiona Auth (Req 1.4).
      final respuesta = await _auth.signUp(
        nombre: nombre,
        apellidos: apellidos,
        email: email.trim(),
        password: password,
      );

      // Si el proyecto exige confirmación por correo, Auth crea el usuario pero
      // NO abre sesión. Sin sesión, RLS impediría leer el perfil, así que se
      // devuelve `null` para que la UI avise de que revise su correo.
      if (respuesta.session == null) {
        return null;
      }

      // Si se proporciona foto, se sube al bucket `avatars` y se asocia la URL
      // pública al perfil recién creado por el trigger de backend (Req 1.7).
      if (foto != null) {
        final bytes = await foto.readAsBytes();
        final fotoUrl = await _profiles.uploadAvatar(
          bytes,
          fileExtension: _extensionDe(foto),
          contentType: foto.mimeType,
        );
        await _profiles.updateMyProfile(<String, dynamic>{'foto_url': fotoUrl});
      }

      // Devuelve el perfil resultante (saldo_clases=10/estado='activo' por el
      // trigger de la migración 0002).
      final row = await _profiles.fetchMyProfile();
      return _mapRowToProfile(row);
    } on AuthException catch (e) {
      throw _mapAuthExceptionSignUp(e);
    }
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw _mapAuthExceptionSignIn(e);
    }

    // Comprobación defensiva del estado de la cuenta (Req 2.3). La restricción
    // real se refuerza en el backend; aquí se traduce a `Failure` de dominio si
    // el perfil está suspendido.
    final row = await _profiles.fetchMyProfile();
    final perfil = _mapRowToProfile(row);
    if (perfil.estado == EstadoUsuario.suspendido) {
      await _signOutSilencioso();
      throw const CuentaSuspendidaFailure();
    }
    return perfil;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> requestPasswordReset(String email) async {
    // Respuesta SIEMPRE genérica: la operación nunca revela si el email existe
    // (Req 9.1). Los errores del SDK se normalizan para no filtrar existencia.
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException {
      // Se ignora: devolver un error aquí podría revelar si la cuenta existe.
    } on Object {
      // Cualquier otro fallo técnico también se normaliza a éxito aparente.
    }
  }

  @override
  Future<void> updatePasswordWithToken(String newPassword) async {
    // Longitud mínima de la nueva contraseña (Req 9.6).
    final passwordFailure = validarPassword(newPassword);
    if (passwordFailure != null) throw passwordFailure;

    try {
      await _auth.updatePassword(newPassword);
    } on AuthException catch (e) {
      throw _mapAuthExceptionReset(e);
    }

    // Un usuario suspendido no puede completar el restablecimiento (Req 9.10).
    final row = await _profiles.fetchMyProfile();
    final perfil = _mapRowToProfile(row);
    if (perfil.estado == EstadoUsuario.suspendido) {
      await _signOutSilencioso();
      throw const CuentaSuspendidaFailure();
    }
  }

  @override
  Stream<AuthState> authStateChanges() => _auth.authStateChanges();

  /// Cierra la sesión ignorando cualquier error, usado tras detectar una cuenta
  /// suspendida para no dejar una sesión activa colgada.
  Future<void> _signOutSilencioso() async {
    try {
      await _auth.signOut();
    } on Object {
      // Se ignora: el fallo relevante es la suspensión, ya señalada.
    }
  }

  /// Traduce una [AuthException] del alta a un [Failure] de dominio (Req 1.4).
  ///
  /// Un email ya registrado se convierte en [EmailEnUsoFailure]; el resto se
  /// trata como credenciales inválidas por defecto.
  Failure _mapAuthExceptionSignUp(AuthException e) {
    if (_esEmailEnUso(e)) {
      return const EmailEnUsoFailure();
    }
    return const CredencialesInvalidasFailure();
  }

  /// Traduce una [AuthException] del inicio de sesión (Req 2.2, 2.3).
  Failure _mapAuthExceptionSignIn(AuthException e) {
    if (_esCuentaSuspendida(e)) {
      return const CuentaSuspendidaFailure();
    }
    return const CredencialesInvalidasFailure();
  }

  /// Traduce una [AuthException] del restablecimiento (Req 9.4, 9.5, 9.10).
  Failure _mapAuthExceptionReset(AuthException e) {
    if (_esCuentaSuspendida(e)) {
      return const CuentaSuspendidaFailure();
    }
    return const TokenInvalidoFailure();
  }

  /// Heurística robusta para detectar un email ya en uso en Supabase Auth.
  ///
  /// Supabase ha variado la señal entre versiones: código `user_already_exists`,
  /// `email_exists`, estado HTTP 422 y/o mensajes como "User already registered".
  bool _esEmailEnUso(AuthException e) {
    final code = e.code?.toLowerCase() ?? '';
    if (code.contains('already') || code.contains('exists')) return true;
    final msg = e.message.toLowerCase();
    return (msg.contains('already') &&
            (msg.contains('registered') || msg.contains('exist'))) ||
        msg.contains('ya está en uso') ||
        msg.contains('ya existe');
  }

  /// Heurística para detectar una cuenta suspendida/bloqueada en Auth.
  ///
  /// Supabase señala estas cuentas con códigos/mensajes como `user_banned`,
  /// "User is banned" o estado HTTP 403.
  bool _esCuentaSuspendida(AuthException e) {
    final code = e.code?.toLowerCase() ?? '';
    if (code.contains('ban') || code.contains('suspend')) return true;
    final msg = e.message.toLowerCase();
    return msg.contains('banned') ||
        msg.contains('suspend') ||
        msg.contains('suspendida') ||
        e.statusCode == '403';
  }

  /// Deriva la extensión de archivo de un [XFile] a partir de su nombre.
  ///
  /// Devuelve `.jpg` por defecto cuando el nombre no incluye extensión, para
  /// garantizar una ruta de Storage con sufijo coherente.
  String _extensionDe(XFile foto) {
    final name = foto.name;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';
    return name.substring(dot);
  }

  /// Mapea una fila cruda de `profiles` a la entidad de dominio [Profile].
  ///
  /// Preserva `metadata` íntegramente (Req 3.5) y traduce las columnas de texto
  /// `estado`/`rol` a sus enumeraciones de dominio.
  Profile _mapRowToProfile(Map<String, dynamic> row) {
    final metadataRaw = row['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};

    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;

    return Profile(
      id: row['id'] as String,
      nombre: row['nombre'] as String,
      apellidos: row['apellidos'] as String,
      fotoUrl: row['foto_url'] as String?,
      email: row['email'] as String,
      saldoClases: (row['saldo_clases'] as num).toInt(),
      estado: EstadoUsuario.desdeValor(row['estado'] as String),
      rol: RolUsuario.desdeValor(row['rol'] as String),
      metadata: metadata,
      createdAt: createdAt,
    );
  }
}
