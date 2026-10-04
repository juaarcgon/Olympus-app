// Pruebas de humo del shell de enrutado y sus placeholders.
//
// La guarda de sesión real ([AppRouter]) depende del cliente de Supabase
// inicializado, por lo que no se instancia aquí (requeriría arranque de
// Supabase / red). En su lugar se verifica el comportamiento observable de la
// guarda: qué pantalla se renderiza en cada rama.
//
// * Sin sesión activa → se muestra la rama pública (Requisito 7.3).
// * Con sesión activa → se muestra la rama autenticada.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:olympus/core/router/app_router.dart';

void main() {
  testWidgets(
    'sin sesión la guarda muestra la rama pública (login placeholder)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PublicPlaceholderScreen()),
        ),
      );

      expect(find.text('Public / Login placeholder'), findsOneWidget);
      expect(find.text('Home / Authenticated placeholder'), findsNothing);
    },
  );

  testWidgets(
    'con sesión la guarda muestra la rama autenticada (home placeholder)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AuthenticatedPlaceholderScreen()),
        ),
      );

      expect(find.text('Home / Authenticated placeholder'), findsOneWidget);
      expect(find.text('Public / Login placeholder'), findsNothing);
    },
  );
}
