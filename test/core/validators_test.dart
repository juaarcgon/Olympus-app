import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/core/utils/utils.dart';

void main() {
  group('esEmailValido', () {
    test('acepta correos con formato válido', () {
      expect(esEmailValido('persona@gimnasio.com'), isTrue);
      expect(esEmailValido('a.b-c_d@sub.dominio.es'), isTrue);
      expect(esEmailValido('  usuario@dominio.io  '), isTrue); // recortado
    });

    test('rechaza correos con formato inválido', () {
      expect(esEmailValido(''), isFalse);
      expect(esEmailValido('sinarroba.com'), isFalse);
      expect(esEmailValido('sin@dominio'), isFalse);
      expect(esEmailValido('con espacio@dominio.com'), isFalse);
      expect(esEmailValido('@dominio.com'), isFalse);
      expect(esEmailValido('usuario@.com'), isFalse);
    });
  });

  group('esPasswordValida', () {
    test('acepta contraseñas de 8 o más caracteres', () {
      expect(esPasswordValida('12345678'), isTrue);
      expect(esPasswordValida('contraseñaLarga'), isTrue);
    });

    test('rechaza contraseñas de menos de 8 caracteres', () {
      expect(esPasswordValida(''), isFalse);
      expect(esPasswordValida('1234567'), isFalse);
    });
  });

  group('validarEmail', () {
    test('devuelve null cuando el correo es válido', () {
      expect(validarEmail('persona@gimnasio.com'), isNull);
    });

    test('devuelve FormatoEmailFailure cuando el correo es inválido', () {
      expect(validarEmail('no-es-email'), const FormatoEmailFailure());
    });
  });

  group('validarPassword', () {
    test('devuelve null cuando la contraseña es válida', () {
      expect(validarPassword('12345678'), isNull);
    });

    test('devuelve PasswordCortaFailure cuando es demasiado corta', () {
      expect(validarPassword('corta'), const PasswordCortaFailure());
    });
  });

  group('Failure equality', () {
    test('mismas subclases con mismo mensaje son iguales', () {
      expect(const EmailEnUsoFailure(), const EmailEnUsoFailure());
      expect(
        const EmailEnUsoFailure().hashCode,
        const EmailEnUsoFailure().hashCode,
      );
    });

    test('subclases distintas no son iguales', () {
      expect(
        const FormatoEmailFailure() == const PasswordCortaFailure(),
        isFalse,
      );
    });

    test('mensajes personalizados afectan a la igualdad', () {
      expect(
        const CredencialesInvalidasFailure('otro') ==
            const CredencialesInvalidasFailure(),
        isFalse,
      );
    });

    test('los mensajes por defecto están en español', () {
      expect(
        const EmailEnUsoFailure().mensaje,
        'El correo electrónico ya está en uso',
      );
      expect(
        const AutoeliminacionFailure().mensaje,
        'Un superadministrador no puede eliminarse a sí mismo',
      );
    });
  });
}
