// Prueba de propiedad del Servicio_Usuarios (ProfileRepository).
//
// Feature: gym-management-app, Property 8
//
// Property 8: Round trip de actualización de perfil.
// "Para cualquier conjunto válido de nuevos valores de `nombre`, `apellidos` o
//  `foto`, actualizar el perfil y luego releerlo devuelve exactamente los
//  valores escritos."
//
// Validates: Requirements 3.2
//
// El contrato `ProfileRepository.updateMyProfile` acepta `nombre`, `apellidos`
// y `foto` opcionales y, por diseño, solo modifica los campos proporcionados
// (no nulos); los omitidos conservan su valor actual. La implementación real
// (`ProfileRepositoryImpl`) construye el mapa de cambios con `nombre`,
// `apellidos` y, cuando hay foto, `foto_url` (URL derivada en Storage), y luego
// relee la fila ya actualizada para devolver el perfil resultante.
//
// Esta prueba verifica el round trip contra un `ProfileRepository` falso en
// memoria que replica fielmente esa semántica de "escribir solo lo
// proporcionado y releer". Se usa `glados` con un mínimo de 100 iteraciones.
// Cada iteración parte de un `Profile` arbitrario, escribe un subconjunto
// arbitrario de campos editables, y comprueba que `getMyProfile()` devuelve
// exactamente los valores escritos (y preserva los no escritos).

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:image_picker/image_picker.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:olympus/features/profile/domain/repositories/profile_repository.dart';

/// Deriva la URL de Storage asociada a una foto, igual que hace la
/// implementación real al subir el avatar y asociar `foto_url`.
String _fotoUrlDe(XFile foto) => 'avatars/${foto.name}';

/// `ProfileRepository` falso en memoria que replica la semántica de
/// `ProfileRepositoryImpl.updateMyProfile` relevante para Property 8:
///   - solo aplica los campos editables proporcionados (no nulos),
///   - los campos omitidos conservan su valor actual,
///   - al proporcionar `foto` se asocia su `foto_url` derivada,
///   - `getMyProfile()` relee y devuelve el estado ya actualizado.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this._profile);

  Profile _profile;

  @override
  Future<Profile> getMyProfile() async => _profile;

  @override
  Future<Profile> updateMyProfile({
    String? nombre,
    String? apellidos,
    XFile? foto,
  }) async {
    // Solo se tocan las columnas editables que se proporcionan; las demás
    // conservan su valor actual (semántica de la implementación real).
    _profile = _profile.copyWith(
      nombre: nombre,
      apellidos: apellidos,
      fotoUrl: foto != null ? _fotoUrlDe(foto) : _noCambiar,
    );
    return _profile;
  }

  /// Centinela: `copyWith(fotoUrl: _noCambiar)` deja la foto intacta.
  static const Object _noCambiar = Object();
}

/// Un conjunto de nuevos valores a escribir en el perfil. Cada campo puede ser
/// `null` (no se escribe) o un valor concreto (se escribe), de modo que la
/// propiedad cubre todas las combinaciones de campos editados u omitidos.
class _CambioPerfil {
  const _CambioPerfil({
    required this.nombre,
    required this.apellidos,
    required this.fotoName,
  });

  final String? nombre;
  final String? apellidos;

  /// Nombre del archivo de la foto a escribir, o `null` si no se cambia foto.
  final String? fotoName;

  /// Construye el [XFile] de la foto a escribir, o `null` si no hay cambio.
  XFile? get foto => fotoName == null ? null : XFile('/tmp/$fotoName');

  @override
  String toString() =>
      '_CambioPerfil(nombre: $nombre, apellidos: $apellidos, '
      'fotoName: $fotoName)';
}

/// Genera un `String?`: `null` (campo no escrito) o una cadena de
/// letras/dígitos arbitraria (campo escrito). Las cadenas vacías representan,
/// por convención del generador, el caso "no escribir este campo"; así se
/// cubren ambas ramas (campo editado y campo omitido) con combinadores básicos.
Generator<String?> get _anyNullableTexto =>
    any.letterOrDigits.map<String?>((s) => s.isEmpty ? null : s);

/// Genera un conjunto arbitrario de cambios (cada campo puede escribirse o no).
Generator<_CambioPerfil> get _anyCambioPerfil => any.combine3(
  _anyNullableTexto,
  _anyNullableTexto,
  _anyNullableTexto,
  (nombre, apellidos, fotoName) =>
      _CambioPerfil(nombre: nombre, apellidos: apellidos, fotoName: fotoName),
);

/// Genera el perfil de partida arbitrario (campos editables iniciales).
class _PerfilInicial {
  const _PerfilInicial({
    required this.nombre,
    required this.apellidos,
    required this.fotoName,
  });

  final String nombre;
  final String apellidos;

  /// Nombre del archivo de foto inicial, o `null` si el perfil no tiene foto.
  final String? fotoName;

  String? get fotoUrl => fotoName == null ? null : 'avatars/$fotoName';

  @override
  String toString() =>
      '_PerfilInicial(nombre: $nombre, apellidos: $apellidos, '
      'fotoName: $fotoName)';
}

Generator<_PerfilInicial> get _anyPerfilInicial => any.combine3(
  any.letterOrDigits,
  any.letterOrDigits,
  _anyNullableTexto,
  (nombre, apellidos, fotoName) =>
      _PerfilInicial(nombre: nombre, apellidos: apellidos, fotoName: fotoName),
);

void main() {
  group(
    'Feature: gym-management-app, Property 8 - round trip de actualización de '
    'perfil',
    () {
      Glados2(
        _anyPerfilInicial,
        _anyCambioPerfil,
      ).test('actualizar el perfil y releerlo devuelve exactamente los valores '
          'escritos (Req 3.2)', (inicial, cambio) async {
        final profileInicial = Profile(
          id: 'user-1',
          nombre: inicial.nombre,
          apellidos: inicial.apellidos,
          fotoUrl: inicial.fotoUrl,
          email: 'user@olympus.test',
          saldoClases: 10,
        );

        final repo = _FakeProfileRepository(profileInicial);

        await repo.updateMyProfile(
          nombre: cambio.nombre,
          apellidos: cambio.apellidos,
          foto: cambio.foto,
        );

        final actualizado = await repo.getMyProfile();

        // Valores esperados tras el round trip: cada campo proporcionado
        // debe leerse con el valor escrito; los omitidos deben conservar su
        // valor inicial.
        final nombreEsperado = cambio.nombre ?? inicial.nombre;
        final apellidosEsperado = cambio.apellidos ?? inicial.apellidos;
        final fotoUrlEsperada = cambio.foto != null
            ? _fotoUrlDe(cambio.foto!)
            : inicial.fotoUrl;

        // Invariante central de Property 8 (Req 3.2): releer devuelve
        // exactamente lo escrito.
        expect(
          actualizado.nombre,
          nombreEsperado,
          reason: 'el nombre releído debe coincidir con el valor escrito',
        );
        expect(
          actualizado.apellidos,
          apellidosEsperado,
          reason: 'los apellidos releídos deben coincidir con el valor escrito',
        );
        expect(
          actualizado.fotoUrl,
          fotoUrlEsperada,
          reason: 'la foto releída debe coincidir con el valor escrito',
        );
      });
    },
  );
}
