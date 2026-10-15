// Prueba de propiedad de la seguridad y control de acceso a datos (RLS).
//
// Feature: gym-management-app, Property 20
//
// Property 20: Sin sesión no hay acceso a datos de usuario.
// "Para cualquier petición de datos de usuario sin una sesión activa, el acceso
//  se deniega (no se devuelve ninguna fila)."
//
// Validates: Requirements 7.3
//
// La propiedad se verifica contra el modelo de control de acceso puro
// `filasVisiblesPara` / `accesoConcedido` (espejo en memoria de la política RLS
// de SELECT sobre `profiles`: `USING (auth.uid() = id OR es_superadmin())` sin
// ninguna política para el rol `anon`; ver design.md, "Security and RLS
// Strategy", y `supabase/migrations/0003_rls.sql`). La aplicación real de RLS
// se refuerza con las pruebas de integración (tarea 12.3).
//
// Se usa `glados` con un mínimo de 100 iteraciones. Cada iteración construye
// una petición *sin Sesion activa* (solicitante nulo, rol `anon`) para un id de
// objetivo arbitrario y comprueba que no se devuelve ninguna fila y que el
// acceso queda denegado, para *cualquier* id de usuario objetivo.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:olympus/features/profile/domain/data_access_control.dart';

/// Genera un identificador de Usuario objetivo arbitrario (no vacío).
Generator<String> get _anyUserId =>
    any.letterOrDigits.map((s) => s.isEmpty ? 'user-0' : s);

void main() {
  group('Feature: gym-management-app, Property 20 - sin sesión no hay acceso a '
      'datos de usuario', () {
    Glados(_anyUserId).test(
      'una petición sin Sesion activa no devuelve ninguna fila para '
      'cualquier id de usuario objetivo (Req 7.3)',
      (objetivoId) {
        // Precondición de la propiedad: no hay Sesion activa (rol `anon`,
        // sin JWT). Se modela con un solicitante nulo.
        final peticion = PeticionDatosUsuario(
          solicitante: null,
          objetivoId: objetivoId,
        );

        // Comprobación de consistencia del modelo: la petición es,
        // efectivamente, una petición sin sesión.
        expect(
          peticion.sinSesion,
          isTrue,
          reason: 'la petición debe modelar la ausencia de sesión',
        );

        // Invariante central de Property 20 (Req 7.3): sin sesión no se
        // devuelve ninguna fila, para *cualquier* id de objetivo.
        expect(
          filasVisiblesPara(peticion),
          0,
          reason:
              'sin sesión activa no debe devolverse ninguna fila para el '
              'objetivo $objetivoId',
        );

        // Y, equivalentemente, el acceso queda denegado.
        expect(
          accesoConcedido(peticion),
          isFalse,
          reason: 'sin sesión activa el acceso debe denegarse',
        );
      },
    );
  });
}
