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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admin/presentation/providers/admin_providers.dart';
import '../../features/admin/presentation/screens/screens.dart';
import '../../features/auth/presentation/screens/screens.dart';
import '../../features/profile/domain/entities/profile.dart';
import '../../features/profile/presentation/providers/profile_providers.dart';
import '../../features/profile/presentation/screens/screens.dart';
import '../../features/reservas/presentation/screens/screens.dart';

/// Widget raíz del shell de enrutado con guarda de sesión.
///
/// Escucha `onAuthStateChange` y reconstruye el árbol para mostrar la rama
/// pública, la de recuperación o la autenticada según el estado de la sesión.
class AppRouter extends ConsumerStatefulWidget {
  /// Crea el shell de enrutado.
  const AppRouter({super.key});

  @override
  ConsumerState<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<AppRouter> {
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;

  /// Id del usuario de la sesión anterior, para detectar cambios de cuenta.
  String? _usuarioAnterior;

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
    _usuarioAnterior = _session?.user.id;

    // La guarda reacciona a cualquier cambio de autenticación (login, logout,
    // refresco de token, restablecimiento de contraseña, etc.).
    _authSubscription = auth.onAuthStateChange.listen((AuthState state) {
      if (!mounted) return;

      // Si cambia el usuario de la sesión (login de otra cuenta, logout o un
      // nuevo registro con sesión), se invalida el estado de usuario cacheado
      // para que el perfil y el panel de administración se recarguen desde
      // cero y no se muestren datos del usuario anterior.
      final nuevoUsuario = state.session?.user.id;
      if (nuevoUsuario != _usuarioAnterior) {
        _usuarioAnterior = nuevoUsuario;
        ref.invalidate(profileNotifierProvider);
        ref.invalidate(adminNotifierProvider);
      }

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
/// autenticadas en una [NavigationBar]. Siempre muestra las pestañas
/// "Calendario" ([CalendarioScreen]) y "Perfil" ([ProfileScreen]); además, si
/// el Usuario actual es superadministrador, añade una tercera pestaña
/// "Administración" ([AdminScreen]) (Req 5.3). Para los Usuarios estándar la
/// barra conserva únicamente las dos pestañas.
///
/// El rol se obtiene de [profileNotifierProvider]; mientras el perfil carga o
/// si falla, se asume que NO es superadministrador y la pestaña permanece
/// oculta. El flujo de recuperación de contraseña permanece intacto porque
/// [AppRouter] lo resuelve antes de llegar aquí.
class HomeShell extends ConsumerStatefulWidget {
  /// Crea el contenedor de la zona autenticada.
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Índice de la pestaña activa (0 = Calendario, 1 = Perfil,
  /// 2 = Administración si procede).
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    // Determina si el Usuario actual es superadministrador para decidir si se
    // muestra la pestaña de administración (Req 5.3). Mientras carga o si hay
    // error se asume que no lo es.
    final esSuperadmin = ref
        .watch(profileNotifierProvider)
        .maybeWhen(
          data: (Profile profile) => profile.esSuperadmin,
          orElse: () => false,
        );

    // Pantallas y destinos base (siempre presentes).
    final pantallas = <Widget>[
      const CalendarioScreen(),
      const ProfileScreen(),
      if (esSuperadmin) const AdminScreen(),
    ];

    final destinos = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Calendario',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Perfil',
      ),
      if (esSuperadmin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Administración',
        ),
    ];

    // Si el rol deja de ser superadmin (p. ej. tras cerrar sesión) y la pestaña
    // activa ya no existe, se vuelve a una pestaña válida.
    final indiceSeguro = _indice.clamp(0, pantallas.length - 1);

    return Scaffold(
      body: IndexedStack(index: indiceSeguro, children: pantallas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indiceSeguro,
        onDestinationSelected: (indice) => setState(() => _indice = indice),
        destinations: destinos,
      ),
    );
  }
}
