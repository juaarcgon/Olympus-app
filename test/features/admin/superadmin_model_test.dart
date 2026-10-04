// Prueba de propiedad del modelo puro de concesión de superadministrador.
//
// Feature: gym-management-app, Property 12
//
// Property 12: Como máximo dos superadministradores.
// "Para cualquier secuencia de concesiones del rol de superadministrador, el
//  número de usuarios con rol == 'superadmin' nunca supera dos (2); todo
//  intento de conceder el rol cuando ya existen dos se rechaza."
//
// Validates: Requirements 5.1, 5.2
//
// La propiedad se verifica contra el modelo de dominio puro
// [SuperadminEstado] (espejo de la RPC `conceder_superadmin`) usando `glados`
// con un mínimo de 100 iteraciones. Cada iteración genera una secuencia
// arbitraria de concesiones sobre un conjunto de usuarios y comprueba la
// invariante tras cada paso.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/admin/domain/superadmin_model.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Conjunto fijo de ids de usuario sobre el que se generan las concesiones.
///
/// Se usa un conjunto acotado (mayor que el límite de 2) para que las
/// secuencias generadas ejerciten de forma frecuente el caso de rechazo al
/// alcanzar el máximo.
const _usuarios = ['u1', 'u2', 'u3', 'u4', 'u5'];

/// Generador de una concesión: el índice (0..n-1) de un usuario del conjunto.
///
/// Se genera un entero no negativo y se reduce con módulo al rango de
/// [_usuarios], obteniendo así un id válido para cada operación.
Generator<int> get _anyIndiceUsuario =>
    any.positiveIntOrZero.map((n) => n % _usuarios.length);

/// Generador de una secuencia arbitraria de concesiones (lista de índices).
Generator<List<int>> get _anySecuencia => any.list(_anyIndiceUsuario);

void main() {
  group('Feature: gym-management-app, Property 12 - máximo 2 superadmins', () {
    Glados(_anySecuencia).test(
      'tras cualquier secuencia de concesiones nunca hay más de 2 superadmins '
      'y toda concesión con 2 ya existentes se rechaza (Req 5.1, 5.2)',
      (secuencia) {
        // Estado inicial: todos los usuarios con rol estándar.
        var estado = SuperadminEstado({
          for (final id in _usuarios) id: RolUsuario.usuario,
        });

        for (final indice in secuencia) {
          final usuario = _usuarios[indice];
          final habiaDos = estado.totalSuperadmins >= kMaxSuperadmins;
          final yaEraSuperadmin = estado.esSuperadmin(usuario);

          final res = estado.concederSuperadmin(usuario);

          // Invariante central (Req 5.1): nunca se superan 2 superadmins.
          expect(
            res.estado.totalSuperadmins,
            lessThanOrEqualTo(kMaxSuperadmins),
          );

          if (habiaDos && !yaEraSuperadmin) {
            // Req 5.2: conceder a un nuevo usuario con 2 ya existentes se
            // rechaza con MaxSuperadminsFailure y no altera el estado.
            expect(res.esExito, isFalse);
            expect(res.failure, isA<MaxSuperadminsFailure>());
            expect(res.estado.totalSuperadmins, equals(kMaxSuperadmins));
            expect(res.estado.esSuperadmin(usuario), isFalse);
          } else if (yaEraSuperadmin) {
            // Idempotencia: conceder a quien ya es superadmin no cambia nada.
            expect(res.esExito, isTrue);
            expect(res.estado.esSuperadmin(usuario), isTrue);
            expect(
              res.estado.totalSuperadmins,
              equals(estado.totalSuperadmins),
            );
          } else {
            // Había hueco: la concesión tiene éxito y el usuario pasa a serlo.
            expect(res.esExito, isTrue);
            expect(res.estado.esSuperadmin(usuario), isTrue);
          }

          // Avanza el estado para la siguiente concesión de la secuencia.
          estado = res.estado;
        }

        // Invariante final tras toda la secuencia (Req 5.1).
        expect(estado.totalSuperadmins, lessThanOrEqualTo(kMaxSuperadmins));
      },
    );
  });
}
