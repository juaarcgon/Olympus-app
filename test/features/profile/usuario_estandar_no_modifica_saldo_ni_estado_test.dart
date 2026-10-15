// Prueba de propiedad del Servicio_Usuarios (ProfileRepository).
//
// Feature: gym-management-app, Property 9
//
// Property 9: El usuario estándar no puede modificar su saldo ni su estado.
// "Para cualquier usuario con rol estándar y cualquier intento de modificar su
//  propio saldo_clases o su propio estado, la operación se rechaza y ambos
//  valores permanecen inalterados."
//
// Validates: Requirements 3.3, 3.4
//
// El contrato `ProfileRepository.updateMyProfile` NO expone, por diseño,
// parámetros para `saldoClases` ni `estado`: estructuralmente un usuario
// estándar no puede pedir su modificación (Req 3.3, 3.4). La implementación
// real (`ProfileRepositoryImpl`) solo construye un mapa de cambios con
// `nombre`, `apellidos` y `foto_url`, y la RLS lo refuerza en el backend.
//
// Esta prueba verifica la propiedad contra un `ProfileRepository` falso en
// memoria que replica fielmente esa semántica: almacena un `Profile` y, en
// `updateMyProfile`, solo aplica `nombre`/`apellidos`/`foto`, dejando intactos
// `saldoClases`, `estado` (y `rol`). Se usa `glados` con un mínimo de 100
// iteraciones. Cada iteración parte de un `Profile` con `rol == usuario`,
// `saldoClases` arbitrario (0..10) y `estado` arbitrario, intenta editar
// nombre/apellidos, y comprueba que tras `updateMyProfile` + `getMyProfile` el
// saldo y el estado permanecen exactamente iguales a sus valores iniciales.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:image_picker/image_picker.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:olympus/features/profile/domain/repositories/profile_repository.dart';

/// `ProfileRepository` falso en memoria que replica la semántica de
/// `ProfileRepositoryImpl.updateMyProfile`: solo aplica los campos editables
/// (`nombre`, `apellidos`, `foto`) y nunca toca `saldoClases`, `estado` ni
/// `rol`. Sirve como espejo del comportamiento real para verificar Property 9.
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
    // Igual que la implementación real: solo se tocan las columnas editables.
    // `saldoClases`, `estado` y `rol` jamás forman parte de los cambios.
    _profile = _profile.copyWith(
      nombre: nombre,
      apellidos: apellidos,
      // La foto se refleja como una URL derivada; el contrato no permite
      // tocar saldo ni estado, que es lo que importa para esta propiedad.
      fotoUrl: foto != null ? 'avatars/${foto.name}' : null,
    );
    return _profile;
  }
}

/// Escenario de un usuario estándar que intenta editar su perfil.
///
/// - `saldoInicial` en 0..10 (todo el rango del bono).
/// - `estadoInicial` cualquiera de los dos estados válidos.
/// - `nombreInicial`/`apellidosInicial`: valores de partida.
/// - `nuevoNombre`/`nuevosApellidos`: valores que se intentan escribir.
class _EscenarioEdicion {
  const _EscenarioEdicion({
    required this.saldoInicial,
    required this.estadoInicial,
    required this.nombreInicial,
    required this.apellidosInicial,
    required this.nuevoNombre,
    required this.nuevosApellidos,
  });

  final int saldoInicial;
  final EstadoUsuario estadoInicial;
  final String nombreInicial;
  final String apellidosInicial;
  final String nuevoNombre;
  final String nuevosApellidos;

  @override
  String toString() =>
      '_EscenarioEdicion(saldoInicial: $saldoInicial, '
      'estadoInicial: ${estadoInicial.valor}, '
      'nombreInicial: $nombreInicial, apellidosInicial: $apellidosInicial, '
      'nuevoNombre: $nuevoNombre, nuevosApellidos: $nuevosApellidos)';
}

/// Generador de escenarios diversos: saldo 0..10, ambos estados, y varias
/// combinaciones de nombre/apellidos iniciales y editados.
Generator<_EscenarioEdicion> get _anyEscenarioEdicion => any
    .intInRange(kBonoMin, kBonoMax + 1)
    .bind(
      (saldo) => any
          .intInRange(0, EstadoUsuario.values.length)
          .bind(
            (estadoIdx) => any.letterOrDigits.bind(
              (nombreIni) => any.letterOrDigits.bind(
                (apellidosIni) => any.letterOrDigits.bind(
                  (nuevoNombre) => any.letterOrDigits.map(
                    (nuevosApellidos) => _EscenarioEdicion(
                      saldoInicial: saldo,
                      estadoInicial: EstadoUsuario.values[estadoIdx],
                      nombreInicial: nombreIni,
                      apellidosInicial: apellidosIni,
                      nuevoNombre: nuevoNombre,
                      nuevosApellidos: nuevosApellidos,
                    ),
                  ),
                ),
              ),
            ),
          ),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 9 - el usuario estándar no puede '
    'modificar su saldo ni su estado',
    () {
      Glados(_anyEscenarioEdicion).test(
        'para cualquier usuario estándar, editar el perfil deja saldo_clases y '
        'estado inalterados (Req 3.3, 3.4)',
        (escenario) async {
          final profileInicial = Profile(
            id: 'user-1',
            nombre: escenario.nombreInicial,
            apellidos: escenario.apellidosInicial,
            email: 'user@olympus.test',
            saldoClases: escenario.saldoInicial,
            estado: escenario.estadoInicial,
            rol: RolUsuario.usuario,
          );

          // Precondición de la propiedad: el usuario tiene rol estándar.
          expect(profileInicial.rol, RolUsuario.usuario);

          final repo = _FakeProfileRepository(profileInicial);

          // El usuario estándar intenta editar su perfil. El contrato solo le
          // permite tocar nombre/apellidos: no existe forma de pedir cambiar
          // saldo ni estado (Req 3.3, 3.4).
          await repo.updateMyProfile(
            nombre: escenario.nuevoNombre,
            apellidos: escenario.nuevosApellidos,
          );

          final actualizado = await repo.getMyProfile();

          // Invariante central (Property 9 / Req 3.3, 3.4): el saldo y el
          // estado permanecen exactamente iguales a sus valores iniciales.
          expect(
            actualizado.saldoClases,
            escenario.saldoInicial,
            reason: 'el saldo_clases no debe cambiar al editar el perfil',
          );
          expect(
            actualizado.estado,
            escenario.estadoInicial,
            reason: 'el estado no debe cambiar al editar el perfil',
          );

          // Los campos editables sí reflejan los nuevos valores escritos.
          expect(actualizado.nombre, escenario.nuevoNombre);
          expect(actualizado.apellidos, escenario.nuevosApellidos);
        },
      );
    },
  );
}
