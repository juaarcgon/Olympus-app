// Prueba de propiedad del Servicio_Usuarios (ProfileRepository).
//
// Feature: gym-management-app, Property 10
//
// Property 10: El modelo de usuario es ampliable (preservación de metadata).
// "Para cualquier objeto JSON arbitrario añadido a `metadata`, al guardarlo y
//  releer el perfil los campos conocidos permanecen intactos y el contenido de
//  `metadata` se preserva íntegramente (round trip)."
//
// Validates: Requirements 3.5
//
// El modelo de usuario `Profile` es ampliable: además de las columnas conocidas
// (`nombre`, `apellidos`, `foto_url`, `email`, `saldo_clases`, `estado`, `rol`,
// `created_at`) conserva un mapa `metadata` arbitrario que se persiste en la
// columna `jsonb` `metadata` de la tabla `profiles` (diseño: Data Models). La
// capa de datos (`ProfileRepositoryImpl._mapRowToProfile`) copia ese mapa tal
// cual al releer la fila, de modo que cualquier contenido ampliable sobrevive
// al round trip DB <-> dominio.
//
// Esta prueba verifica el round trip contra una fuente de datos falsa en
// memoria que replica fielmente esa semántica de serialización:
//   - al "guardar", el `Profile` se convierte en una fila cruda
//     (`Map<String, dynamic>`) tal y como la almacena Postgres, con `metadata`
//     como objeto JSON y `estado`/`rol` como texto;
//   - al "releer", la fila se mapea de vuelta a `Profile` con la MISMA lógica
//     que usa la implementación real (`metadata` -> `Map<String, dynamic>.from`,
//     `estado`/`rol` -> enum, `saldo_clases` -> int).
// Se usa `glados` con un mínimo de 100 iteraciones. Cada iteración parte de un
// `Profile` con un objeto JSON arbitrario en `metadata`, hace el round trip y
// comprueba que (a) los campos conocidos permanecen intactos y (b) el contenido
// de `metadata` se preserva íntegramente.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Serializa un [Profile] a una fila cruda (`Map<String, dynamic>`) tal y como
/// la almacena/devuelve Postgres: `metadata` como objeto JSON, `estado`/`rol`
/// como texto y `created_at` como ISO-8601. Espejo inverso del mapeo real.
Map<String, dynamic> _profileToRow(Profile p) => <String, dynamic>{
  'id': p.id,
  'nombre': p.nombre,
  'apellidos': p.apellidos,
  'foto_url': p.fotoUrl,
  'email': p.email,
  'saldo_clases': p.saldoClases,
  'estado': p.estado.valor,
  'rol': p.rol.valor,
  // La columna `jsonb` conserva el objeto JSON tal cual (campos ampliables).
  'metadata': Map<String, dynamic>.from(p.metadata),
  'created_at': p.createdAt?.toIso8601String(),
};

/// Mapea una fila cruda de `profiles` a [Profile] con la MISMA lógica que
/// `ProfileRepositoryImpl._mapRowToProfile`: preserva `metadata` íntegramente
/// (Req 3.5) y traduce las columnas de texto `estado`/`rol` a sus enums.
Profile _rowToProfile(Map<String, dynamic> row) {
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

/// Realiza el round trip completo guardar -> releer sobre un [Profile].
Profile _roundTrip(Profile p) => _rowToProfile(_profileToRow(p));

/// Genera un valor JSON escalar arbitrario (string, int, double, bool o null),
/// cubriendo los tipos admisibles como hojas de un objeto `jsonb`.
Generator<Object?> get _anyJsonScalar => any.oneOf(<Generator<Object?>>[
  any.letterOrDigits,
  any.int,
  any.double.map<Object?>((d) => d.isFinite ? d : 0.0),
  any.bool,
  any.always<Object?>(null),
]);

/// Genera un objeto JSON arbitrario para `metadata`: un mapa de claves de texto
/// a valores que pueden ser escalares, listas de escalares u objetos anidados
/// de un nivel. Esto cubre la ampliabilidad del modelo (campos futuros
/// arbitrarios) sin perder determinismo en la comparación del round trip.
Generator<Map<String, dynamic>> get _anyJsonMetadata {
  final anyValue = any.oneOf(<Generator<Object?>>[
    _anyJsonScalar,
    any.list(_anyJsonScalar).map<Object?>((l) => List<Object?>.from(l)),
    any
        .map(any.letterOrDigits, _anyJsonScalar)
        .map<Object?>((m) => Map<String, dynamic>.from(m)),
  ]);
  return any
      .map(any.letterOrDigits, anyValue)
      .map((m) => Map<String, dynamic>.from(m));
}

/// Escenario arbitrario: campos conocidos variados + objeto `metadata` JSON
/// arbitrario que representa las extensiones futuras del modelo.
class _EscenarioMetadata {
  const _EscenarioMetadata({
    required this.nombre,
    required this.apellidos,
    required this.email,
    required this.saldoClases,
    required this.estadoIdx,
    required this.rolIdx,
    required this.metadata,
  });

  final String nombre;
  final String apellidos;
  final String email;
  final int saldoClases;
  final int estadoIdx;
  final int rolIdx;
  final Map<String, dynamic> metadata;

  EstadoUsuario get estado => EstadoUsuario.values[estadoIdx];
  RolUsuario get rol => RolUsuario.values[rolIdx];

  @override
  String toString() =>
      '_EscenarioMetadata(nombre: $nombre, apellidos: $apellidos, '
      'email: $email, saldoClases: $saldoClases, estado: ${estado.valor}, '
      'rol: ${rol.valor}, metadata: $metadata)';
}

Generator<_EscenarioMetadata> get _anyEscenarioMetadata =>
    any.letterOrDigits.bind(
      (nombre) => any.letterOrDigits.bind(
        (apellidos) => any.letterOrDigits.bind(
          (email) => any
              .intInRange(kBonoMin, kBonoMax + 1)
              .bind(
                (saldo) => any
                    .intInRange(0, EstadoUsuario.values.length)
                    .bind(
                      (estadoIdx) => any
                          .intInRange(0, RolUsuario.values.length)
                          .bind(
                            (rolIdx) => _anyJsonMetadata.map(
                              (metadata) => _EscenarioMetadata(
                                nombre: nombre,
                                apellidos: apellidos,
                                email: email,
                                saldoClases: saldo,
                                estadoIdx: estadoIdx,
                                rolIdx: rolIdx,
                                metadata: metadata,
                              ),
                            ),
                          ),
                    ),
              ),
        ),
      ),
    );

/// Compara dos valores JSON por estructura y contenido (mapas, listas y
/// escalares), de forma independiente del orden de inserción de claves.
void _expectJsonEquals(
  Object? actual,
  Object? expected, {
  required String reason,
}) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: reason);
    final a = actual as Map;
    expect(a.length, expected.length, reason: '$reason (nº de claves)');
    for (final entry in expected.entries) {
      expect(
        a.containsKey(entry.key),
        isTrue,
        reason: '$reason (clave ${entry.key})',
      );
      _expectJsonEquals(
        a[entry.key],
        entry.value,
        reason: '$reason -> ${entry.key}',
      );
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: reason);
    final a = actual as List;
    expect(a.length, expected.length, reason: '$reason (longitud de lista)');
    for (var i = 0; i < expected.length; i++) {
      _expectJsonEquals(a[i], expected[i], reason: '$reason[$i]');
    }
  } else {
    expect(actual, expected, reason: reason);
  }
}

void main() {
  group('Feature: gym-management-app, Property 10 - el modelo de usuario es '
      'ampliable (round trip de metadata)', () {
    Glados(_anyEscenarioMetadata).test(
      'guardar y releer un perfil con metadata JSON arbitraria preserva los '
      'campos conocidos y el contenido íntegro de metadata (Req 3.5)',
      (escenario) {
        final original = Profile(
          id: 'user-1',
          nombre: escenario.nombre,
          apellidos: escenario.apellidos,
          fotoUrl: null,
          email: escenario.email,
          saldoClases: escenario.saldoClases,
          estado: escenario.estado,
          rol: escenario.rol,
          metadata: escenario.metadata,
          createdAt: DateTime.utc(2024, 1, 1, 12, 30, 45),
        );

        final recuperado = _roundTrip(original);

        // (a) Los campos conocidos permanecen intactos tras el round trip.
        expect(recuperado.id, original.id, reason: 'id intacto');
        expect(recuperado.nombre, original.nombre, reason: 'nombre intacto');
        expect(
          recuperado.apellidos,
          original.apellidos,
          reason: 'apellidos intactos',
        );
        expect(recuperado.fotoUrl, original.fotoUrl, reason: 'fotoUrl intacta');
        expect(recuperado.email, original.email, reason: 'email intacto');
        expect(
          recuperado.saldoClases,
          original.saldoClases,
          reason: 'saldo_clases intacto',
        );
        expect(recuperado.estado, original.estado, reason: 'estado intacto');
        expect(recuperado.rol, original.rol, reason: 'rol intacto');
        expect(
          recuperado.createdAt,
          original.createdAt,
          reason: 'created_at intacto',
        );

        // (b) El contenido de metadata se preserva íntegramente (Req 3.5):
        // mismas claves y mismos valores, estructura JSON incluida.
        _expectJsonEquals(
          recuperado.metadata,
          original.metadata,
          reason: 'el contenido de metadata debe preservarse íntegramente',
        );

        // Refuerzo: igualdad estructural completa de la entidad de dominio.
        expect(
          recuperado,
          original,
          reason: 'el perfil completo debe sobrevivir al round trip',
        );
      },
    );
  });
}
