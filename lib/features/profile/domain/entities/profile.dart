// Entidad de dominio Profile para la app Olympus.
//
// Representa el registro de un Usuario en la tabla `profiles` (espejo de
// `auth.users`). Es un modelo de dominio puro e inmutable: no depende del SDK
// de Supabase. El mapeo DTO <-> dominio ocurre en la capa de datos.
//
// El modelo es ampliable (Req 3.5): además de los campos conocidos conserva un
// mapa `metadata` arbitrario que se preserva íntegramente en los round trips.

/// Estado de un Usuario dentro del Sistema (Req 1.1, 6.2, 6.3).
enum EstadoUsuario {
  /// Usuario operativo que puede iniciar sesión y reservar clases.
  activo,

  /// Usuario dado de baja; no puede iniciar sesión (Req 2.3, 9.10).
  suspendido;

  /// Valor textual tal y como se persiste en la columna `estado`.
  String get valor => name;

  /// Construye el estado a partir de su representación textual persistida.
  ///
  /// Lanza [ArgumentError] si [valor] no corresponde a ningún estado válido.
  static EstadoUsuario desdeValor(String valor) {
    for (final estado in EstadoUsuario.values) {
      if (estado.name == valor) return estado;
    }
    throw ArgumentError.value(valor, 'valor', 'Estado de usuario no válido');
  }
}

/// Rol de un Usuario dentro del Sistema (Req 5).
enum RolUsuario {
  /// Usuario con privilegios estándar.
  usuario,

  /// Usuario con privilegios elevados de gestión (máximo 2 en el Sistema).
  superadmin;

  /// Valor textual tal y como se persiste en la columna `rol`.
  String get valor => name;

  /// Construye el rol a partir de su representación textual persistida.
  ///
  /// Lanza [ArgumentError] si [valor] no corresponde a ningún rol válido.
  static RolUsuario desdeValor(String valor) {
    for (final rol in RolUsuario.values) {
      if (rol.name == valor) return rol;
    }
    throw ArgumentError.value(valor, 'valor', 'Rol de usuario no válido');
  }
}

/// Registro de dominio de un Usuario del gimnasio.
///
/// Inmutable: todos sus campos son `final`. Para derivar una copia modificada
/// se usa [copyWith]. Implementa igualdad estructural por valor.
class Profile {
  const Profile({
    required this.id,
    required this.nombre,
    required this.apellidos,
    required this.email,
    required this.saldoClases,
    this.fotoUrl,
    this.estado = EstadoUsuario.activo,
    this.rol = RolUsuario.usuario,
    this.metadata = const <String, dynamic>{},
    this.createdAt,
  });

  /// Identificador único del Usuario (mismo id que su cuenta de Auth).
  final String id;

  /// Nombre del Usuario (Req 1.1).
  final String nombre;

  /// Apellidos del Usuario (Req 1.1).
  final String apellidos;

  /// Ruta/URL de la foto de perfil en Storage; `null` si no tiene (Req 1.7).
  final String? fotoUrl;

  /// Correo electrónico del Usuario (espejo de `auth.users.email`).
  final String email;

  /// Saldo de clases del bono; invariante 0..10 (Req 1.2, 4.4, 8.10).
  final int saldoClases;

  /// Estado del Usuario: activo o suspendido (Req 1.1, 6.2, 6.3).
  final EstadoUsuario estado;

  /// Rol del Usuario: usuario estándar o superadministrador (Req 5).
  final RolUsuario rol;

  /// Campos ampliables arbitrarios preservados íntegramente (Req 3.5).
  final Map<String, dynamic> metadata;

  /// Fecha de creación del registro; `null` si aún no se conoce.
  final DateTime? createdAt;

  /// Indica si el Usuario tiene rol de superadministrador.
  bool get esSuperadmin => rol == RolUsuario.superadmin;

  /// Indica si el Usuario está activo.
  bool get estaActivo => estado == EstadoUsuario.activo;

  /// Devuelve una copia del perfil con los campos indicados reemplazados.
  ///
  /// Los campos no indicados conservan su valor actual. Para `fotoUrl`, que es
  /// anulable, se usa un valor centinela interno de forma que se distinga
  /// "no modificar" de "fijar a null".
  Profile copyWith({
    String? id,
    String? nombre,
    String? apellidos,
    Object? fotoUrl = _sentinel,
    String? email,
    int? saldoClases,
    EstadoUsuario? estado,
    RolUsuario? rol,
    Map<String, dynamic>? metadata,
    Object? createdAt = _sentinel,
  }) {
    return Profile(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      apellidos: apellidos ?? this.apellidos,
      fotoUrl: identical(fotoUrl, _sentinel)
          ? this.fotoUrl
          : fotoUrl as String?,
      email: email ?? this.email,
      saldoClases: saldoClases ?? this.saldoClases,
      estado: estado ?? this.estado,
      rol: rol ?? this.rol,
      metadata: metadata ?? this.metadata,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          nombre == other.nombre &&
          apellidos == other.apellidos &&
          fotoUrl == other.fotoUrl &&
          email == other.email &&
          saldoClases == other.saldoClases &&
          estado == other.estado &&
          rol == other.rol &&
          _mapEquals(metadata, other.metadata) &&
          createdAt == other.createdAt);

  @override
  int get hashCode => Object.hash(
    id,
    nombre,
    apellidos,
    fotoUrl,
    email,
    saldoClases,
    estado,
    rol,
    _mapHash(metadata),
    createdAt,
  );

  @override
  String toString() =>
      'Profile(id: $id, nombre: $nombre, apellidos: $apellidos, '
      'email: $email, saldoClases: $saldoClases, estado: ${estado.valor}, '
      'rol: ${rol.valor}, metadata: $metadata)';
}

/// Centinela interno para distinguir "no modificar" de "fijar a null" en
/// [Profile.copyWith] para campos anulables.
const Object _sentinel = Object();

/// Igualdad superficial de mapas de metadata (claves y valores).
bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Hash independiente del orden para un mapa de metadata.
int _mapHash(Map<String, dynamic> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
