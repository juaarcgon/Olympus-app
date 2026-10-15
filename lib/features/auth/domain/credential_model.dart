// Modelo de dominio puro del almacenamiento de credenciales para Olympus.
//
// Reúne, como funciones puras en memoria (sin efectos secundarios, sin
// dependencias de Supabase y completamente deterministas), el espejo del
// comportamiento de Supabase Auth respecto a las contraseñas: una contraseña,
// una vez registrada o restablecida, se persiste SIEMPRE como una
// `Contraseña_Cifrada` (un hash no reversible), nunca como texto plano, y la
// verificación de credenciales se realiza comparando hashes, sin usar jamás
// el texto plano persistido.
//
// Supabase Auth es quien aplica realmente el hashing (bcrypt) en el backend;
// este modelo es un espejo determinista que permite verificar la propiedad de
// dominio ("las contraseñas nunca se almacenan ni comparan en texto plano",
// Property 3 / Req 1.3, 2.5, 7.1, 9.7) con pruebas basadas en propiedades,
// de forma consistente con el resto de modelos de dominio de la app
// (`bono_model.dart`, `reservas_model.dart`).

/// Representa una contraseña persistida como `Contraseña_Cifrada` (hash).
///
/// Es el único artefacto que el Sistema guarda de una contraseña (Req 7.1):
/// un [digest] no reversible. El texto plano original NUNCA se conserva.
///
/// Inmutable; implementa igualdad estructural por valor sobre el [digest].
class StoredPassword {
  const StoredPassword(this.digest);

  /// Digest (hash) no reversible de la contraseña. Es lo único persistido.
  final String digest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredPassword &&
          runtimeType == other.runtimeType &&
          digest == other.digest);

  @override
  int get hashCode => digest.hashCode;

  @override
  String toString() => 'StoredPassword($digest)';
}

/// Prefijo que identifica el algoritmo del digest (espejo del `$2...$` de
/// bcrypt que usa Supabase Auth). Hace evidente que el valor persistido es un
/// hash y no la contraseña en claro.
///
/// Se compone únicamente de símbolos no alfanuméricos para que, junto con el
/// cuerpo del digest (también no alfanumérico), el valor persistido completo
/// jamás contenga como subcadena una contraseña alfanumérica (Req 7.1).
const String _digestPrefix = r'$$$';

/// Alfabeto del digest: 16 símbolos NO alfanuméricos.
///
/// Al no contener letras ni dígitos, un digest formado solo con estos símbolos
/// nunca puede contener como subcadena una contraseña (que sí es alfanumérica).
/// Esto refuerza de forma estructural la invariante "el valor persistido no
/// contiene el texto plano" (Req 7.1), más allá de la irreversibilidad del
/// propio hash.
const String _digestAlphabet = '!#%&*+-/:;<=>?@~';

/// Calcula el hash no reversible de [plaintext] (espejo del hashing de Auth).
///
/// Produce un digest determinista de longitud fija a partir de la contraseña,
/// de modo que la misma contraseña siempre genera el mismo digest (para poder
/// verificar credenciales) pero el digest no revela ni contiene el texto
/// plano. La transformación es no inyectiva de forma trivial hacia atrás: a
/// partir del digest no se puede recuperar la contraseña original.
///
/// El digest se codifica con un alfabeto de símbolos no alfanuméricos
/// ([_digestAlphabet]), de modo que jamás contiene como subcadena una
/// contraseña alfanumérica.
///
/// No pretende ser criptográficamente seguro (de eso se encarga Supabase Auth
/// con bcrypt en el backend); su único objetivo es modelar de forma pura y
/// determinista la propiedad "nunca texto plano" para las pruebas.
String hashPassword(String plaintext) {
  // Hash de tipo FNV-1a de 64 bits sobre las unidades de código: determinista,
  // de longitud fija y sin conservar los caracteres originales de la entrada.
  var hash = 0xcbf29ce484222325;
  for (final unit in plaintext.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  // Codifica el hash de 64 bits en 16 nibbles usando el alfabeto no
  // alfanumérico, garantizando longitud fija y ausencia de caracteres
  // alfanuméricos en el digest.
  final buffer = StringBuffer(_digestPrefix);
  for (var shift = 60; shift >= 0; shift -= 4) {
    final nibble = (hash >> shift) & 0xF;
    buffer.write(_digestAlphabet[nibble]);
  }
  return buffer.toString();
}

/// Persiste [plaintext] como `Contraseña_Cifrada` (espejo del registro y del
/// restablecimiento de contraseña).
///
/// Devuelve un [StoredPassword] cuyo digest es el hash de [plaintext]
/// (Req 1.3, 7.1, 9.7). El texto plano no se guarda en ningún campo.
StoredPassword store(String plaintext) =>
    StoredPassword(hashPassword(plaintext));

/// Verifica una credencial comparando hashes (espejo del inicio de sesión).
///
/// Hashea el [intento] y lo compara con el [digest] persistido en [stored]
/// (Req 2.5). En ningún momento se compara ni se accede a un texto plano
/// almacenado: la verificación opera exclusivamente sobre hashes.
bool verify(StoredPassword stored, String intento) =>
    stored.digest == hashPassword(intento);
