/// Enrutado base y guarda de sesión de la aplicación.
///
/// El shell de enrutado decide, en función del estado de autenticación de
/// Supabase, qué rama de la app mostrar:
///
/// * Sin sesión activa → ramas públicas (login / registro / recuperación).
///   Mientras no haya sesión, el usuario nunca ve datos autenticados
///   (Requisito 7.3).
/// * Evento de recuperación de contraseña → pantalla para fijar la nueva
///   contraseña dentro de la sesión de recuperación (Req 9.6/9.7).
/// * Con sesión activa → ramas autenticadas (home / perfil / reservas...).
///
/// La lógica de la guarda se basa en
/// `Supabase.instance.client.auth.onAuthStateChange` y en `currentSession`,
/// observando además el evento `passwordRecovery` para desviar al flujo de
/// restablecimiento.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/screens/screens.dart';
import '../../features/profile/presentation/screens/screens.dart';
import '../../features/reservas/presentation/screens/screens.dart';

/// Widget raíz del shell de enrutado con guarda de sesión.
///
/// Escucha `onAuthStateChange` y reconstruye el árbol para mostrar la rama
/// pública, la de recuperación o la autenticada según el estado de la sesión.
class AppRouter extends StatefulWidget {
  /// Crea el shell de enrutado.
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;

  /// Indica que hay un flujo de recuperación de contraseña en curso: el Usuario
  /// abrió el enlace de restablecimiento y debe fijar una nueva contraseña
  /// (Req 9.6/9.7) antes de continuar a la zona autenticada.
  bool _recuperandoPassword = false;

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
        // Al abrir el enlace de recuperación Supabase emite `passwordRecovery`
        // con una sesión temporal: desviamos a la pantalla de nueva contraseña.
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _recuperandoPassword = true;
        } else if (state.event == AuthChangeEvent.signedOut) {
          _recuperandoPassword = false;
        }
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
    // Prioridad al flujo de recuperación: aunque exista una sesión temporal, el
    // Usuario debe fijar su nueva contraseña primero (Req 9.6/9.7).
    if (_recuperandoPassword) {
      return const ResetPasswordScreen();
    }

    // Sin sesión → ramas públicas; con sesión → ramas autenticadas (Req 7.3).
    final bool isAuthenticated = _session != null;
    return isAuthenticated ? const HomeShell() : const LoginScreen();
  }
}

/// Contenedor de la zona autenticada con navegación por pestañas.
///
/// Mantiene el guard de sesión en [AppRouter] y organiza las pantallas
/// autenticadas en una [BottomNavigationBar] con dos pestañas: "Calendario"
/// ([CalendarioScreen]) y "Perfil" ([ProfileScreen]). El flujo de recuperación
/// de contraseña permanece intacto porque [AppRouter] lo resuelve antes de
/// llegar aquí.
class HomeShell extends StatefulWidget {
  /// Crea el contenedor de la zona autenticada.
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Índice de la pestaña activa (0 = Calendario, 1 = Perfil).
  int _indice = 0;

  /// Pantallas de cada pestaña, preservadas con [IndexedStack] para mantener su
  /// estado al alternar.
  static const List<Widget> _pantallas = <Widget>[
    CalendarioScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indice, children: _pantallas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (indice) => setState(() => _indice = indice),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
