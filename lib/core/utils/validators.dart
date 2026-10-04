// Validadores de entrada para la app Olympus.
//
// Cubren la validación de formato de correo electrónico (Req 1.5) y la
// longitud mínima de la contraseña (Req 1.6, 9.6). Se exponen dos estilos
// de API complementarios y documentados:
//
//  - Predicados booleanos: [esEmailValido] y [esPasswordValida], útiles para
//    validación en línea de formularios (p. ej. `validator` de TextFormField).
//  - Funciones que devuelven `Failure?` (null si es válido): [validarEmail] y
//    [validarPassword], útiles en la capa de repositorio para traducir
//    directamente a errores de dominio tipados antes de llamar a Supabase.

import '../error/failures.dart';

/// Longitud mínima exigida para una contraseña (Req 1.6, 9.6).
///
/// Debe coincidir con `kPasswordMinLength` de `lib/core/config/constants.dart`.
/// Se define aquí localmente para evitar conflictos con la tarea paralela que
/// crea `constants.dart`; mantener ambos valores sincronizados en 8.
const int _passwordMinLength = 8; // == kPasswordMinLength

/// Expresión regular para validar el formato de una dirección de correo.
///
/// Comprueba la estructura básica `local@dominio.tld`: una parte local sin
/// espacios ni arrobas, una arroba, un dominio y al menos un punto con un TLD
/// de dos o más letras. No pretende cubrir el RFC 5322 completo, sino rechazar
/// los formatos claramente inválidos exigidos por el Req 1.5.
final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Devuelve `true` si [email] tiene un formato de correo válido (Req 1.5).
bool esEmailValido(String email) {
  final valor = email.trim();
  if (valor.isEmpty) return false;
  return _emailRegExp.hasMatch(valor);
}

/// Devuelve `true` si [password] cumple la longitud mínima (Req 1.6, 9.6).
bool esPasswordValida(String password) => password.length >= _passwordMinLength;

/// Valida el formato de [email].
///
/// Devuelve `null` si el correo es válido, o un [FormatoEmailFailure] si no
/// cumple el formato de una dirección válida (Req 1.5).
Failure? validarEmail(String email) =>
    esEmailValido(email) ? null : const FormatoEmailFailure();

/// Valida la longitud de [password].
///
/// Devuelve `null` si la contraseña es válida, o un [PasswordCortaFailure] si
/// tiene menos de [_passwordMinLength] caracteres (Req 1.6, 9.6).
Failure? validarPassword(String password) =>
    esPasswordValida(password) ? null : const PasswordCortaFailure();
