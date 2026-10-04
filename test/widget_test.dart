// Pruebas de humo de las ramas de enrutado.
//
// La guarda de sesión real ([AppRouter]) depende del cliente de Supabase
// inicializado, por lo que no se instancia aquí (requeriría arranque de
// Supabase / red). En su lugar se verifica el comportamiento observable de la
// guarda y del contenedor autenticado: qué pantalla se renderiza en cada rama.
//
// * Sin sesión activa → se muestra la rama pública: la pantalla de inicio de
//   sesión [LoginScreen] (Requisito 7.3).
// * Con sesión activa → se muestra la rama autenticada: el contenedor
//   [HomeShell] con pestañas "Calendario" y "Perfil". Su pestaña inicial es el
//   calendario ([CalendarioScreen]), cuyos `AsyncNotifier` consultan Supabase
//   al construirse, así que se sobrescriben con estados de carga para aislar la
//   prueba de la red.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:olympus/core/router/router.dart';
import 'package:olympus/features/auth/presentation/screens/screens.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:olympus/features/profile/presentation/providers/profile_providers.dart';
import 'package:olympus/features/reservas/presentation/providers/providers.dart';

/// `AsyncNotifier` de perfil que permanece en carga para aislar la prueba de la
/// red (no consulta Supabase al construirse).
class _CargandoProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile> build() {
    // Nunca completa: mantiene el estado en `AsyncLoading`.
    return Completer<Profile>().future;
  }
}

/// `AsyncNotifier` del día que permanece en carga para aislar la prueba de la
/// red (no consulta Supabase al construirse).
class _CargandoDiaReservasNotifier extends DiaReservasNotifier {
  @override
  Future<DiaReservasView> build() {
    // Nunca completa: mantiene el estado en `AsyncLoading`.
    return Completer<DiaReservasView>().future;
  }
}

void main() {
  testWidgets(
    'sin sesión la guarda muestra la rama pública (inicio de sesión)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );

      // La pantalla de inicio de sesión muestra su título y el botón de acción.
      expect(find.text('Iniciar sesión'), findsWidgets);
      expect(find.text('Mi perfil'), findsNothing);
    },
  );

  testWidgets(
    'con sesión la rama autenticada muestra el contenedor con pestañas '
    'Calendario y Perfil',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileNotifierProvider.overrideWith(_CargandoProfileNotifier.new),
            diaReservasProvider.overrideWith(_CargandoDiaReservasNotifier.new),
          ],
          child: const MaterialApp(home: HomeShell()),
        ),
      );

      // La pestaña inicial es el calendario: su barra superior y las dos
      // etiquetas de navegación están presentes.
      expect(find.text('Calendario'), findsWidgets);
      expect(find.text('Perfil'), findsOneWidget);
      // Aún no se muestra la pantalla de perfil (pestaña no seleccionada).
      expect(find.text('Mi perfil'), findsNothing);
      expect(find.text('Iniciar sesión'), findsNothing);
    },
  );
}
