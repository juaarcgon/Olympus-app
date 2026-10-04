/// Enrutado base y guarda de sesión de la aplicación.
///
/// El shell de enrutado decide, en función del estado de autenticación de
/// Supabase, qué rama de la app mostrar:
///
/// * Sin sesión activa → ramas públicas (login / registro). Mientras no haya
///   sesión, el usuario nunca ve datos autenticados (Requisito 7.3).
/// * Con sesión activa → ramas autenticadas (home / perfil / reservas...).
///
/// Como las pantallas reales de autenticación y perfil se implementan en grupos
/// posteriores del plan, aquí se usan *placeholders* mínimos
/// ([PublicPlaceholderScreen] y [AuthenticatedPlaceholderScreen]) que luego se
/// sustituirán. La lógica de la guarda —basada en
/// `Supabase.instance.client.auth.onAuthStateChange` y en `currentSession`— es
/// la definitiva y no debe cambiar al reemplazar las pantallas.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Widget raíz del shell de enrutado con guarda de sesión.
///
/// Escucha `onAuthStateChange` y reconstruye el árbol para mostrar la rama
/// pública o la autenticada según exista o no una [Session] activa.
class AppRouter extends StatefulWidget {
  /// Crea el shell de enrutado.
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;

  @override
  void initState() {
    super.initState();

    final GoTrueClient auth = Supabase.instance.client.auth;

    // Estado inicial: puede haber ya una sesión restaurada al arrancar.
    _session = auth.currentSession;

    // La guarda reacciona a cualquier cambio de autenticación (login, logout,
    // refresco de token, restablecimiento de contraseña, etc.).
    _authSubscription = auth.onAuthStateChange.listen((AuthState state) {
      if (!mounted) return;
      setState(() {
        _session = state.session;
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sin sesión → ramas públicas; con sesión → ramas autenticadas (Req 7.3).
    final bool isAuthenticated = _session != null;
    return isAuthenticated
        ? const AuthenticatedPlaceholderScreen()
        : const PublicPlaceholderScreen();
  }
}

/// Placeholder de la rama pública (no autenticada).
///
/// Se reemplazará por las pantallas reales de login/registro en el grupo de
/// Auth (tarea 6.10).
class PublicPlaceholderScreen extends StatelessWidget {
  /// Crea la pantalla placeholder pública.
  const PublicPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Public / Login placeholder')),
    );
  }
}

/// Placeholder de la rama autenticada.
///
/// Se reemplazará por el home real (perfil, reservas, administración...) en los
/// grupos posteriores del plan.
class AuthenticatedPlaceholderScreen extends StatelessWidget {
  /// Crea la pantalla placeholder autenticada.
  const AuthenticatedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Home / Authenticated placeholder')),
    );
  }
}
