# Implementation Plan: Gym Management App (Olympus)

## Overview

Este plan convierte el diseño en una serie de pasos de codificación incrementales para una aplicación **Flutter + Supabase**. El primer grupo levanta el **esqueleto del proyecto** (proyecto Flutter, dependencias, estructura de carpetas, inicialización de Supabase y las migraciones SQL base con constraints, trigger, helper `es_superadmin()` y RLS). Los grupos siguientes implementan cada feature de forma incremental (auth, perfil, bono, administración/superadmin y reservas con lista de espera), cableando cada paso a los anteriores y a las propiedades de corrección del diseño.

La lógica de negocio del bono y las reservas se encapsula en un **modelo de dominio puro en memoria** (espejo de las RPC de PostgreSQL). Las pruebas basadas en propiedades (PBT) con `glados` validan ese modelo; las pruebas de integración verifican que las RPC reales se comportan igual. Cada prueba de propiedad lleva la etiqueta de trazabilidad **Feature: gym-management-app, Property N**.

Lenguaje de implementación: **Dart (Flutter)** para el cliente y **SQL (PostgreSQL)** para el backend Supabase, tal como fija el diseño.

## Tasks

- [x] 1. Esqueleto del proyecto: inicialización, dependencias y estructura
  - [x] 1.1 Inicializar el proyecto Flutter y declarar dependencias
    - Crear el proyecto Flutter en la raíz del workspace (`Olympus`)
    - Añadir en `pubspec.yaml`: `supabase_flutter`, `flutter_riverpod`, `image_picker`
    - Añadir en `dev_dependencies`: `glados` (property testing) y `flutter_test`
    - Ejecutar `flutter pub get` para resolver dependencias
    - _Requirements: 3.5_
    - _Design: Decisiones de diseño destacadas (Riverpod, Supabase, image_picker, glados)_

  - [x] 1.2 Crear la estructura de carpetas por features del diseño
    - Crear `lib/core/{config,error,router,theme,utils}`
    - Crear `lib/features/{auth,profile,bono,admin,reservas}` cada una con subcarpetas `data/{datasources,repositories}`, `domain/{entities,repositories}` y `presentation/{providers,screens}`
    - Crear `lib/shared/{widgets,models}`
    - Crear `supabase/migrations/` y `test/features/`
    - Añadir archivos barrel/placeholder mínimos para que cada carpeta sea importable
    - _Requirements: 3.5_
    - _Design: Estructura de carpetas recomendada (esqueleto del proyecto)_

  - [x] 1.3 Definir configuración central y constantes
    - Implementar `lib/core/config/supabase_config.dart`: lectura de `SUPABASE_URL` y `SUPABASE_ANON_KEY` desde variables de entorno (`String.fromEnvironment`) y función `initSupabase()`
    - Implementar `lib/core/config/constants.dart`: `kBonoMax = 10`, `kBonoMin = 0`, `kAforoMax = 10`, `kWaitlistMax = 20`, `kPasswordMinLength = 8`, `kCancelacionHoras = 2`
    - _Requirements: 4.4, 8.1, 8.12, 1.6_
    - _Design: core/config_

  - [x] 1.4 Definir tipos de error de dominio y validadores
    - Implementar `lib/core/error/failures.dart` con la jerarquía `Failure`: `EmailEnUsoFailure`, `FormatoEmailFailure`, `PasswordCortaFailure`, `CredencialesInvalidasFailure`, `CuentaSuspendidaFailure`, `SinClasesFailure`, `ListaEsperaLlenaFailure`, `ReservaDuplicadaFailure`, `AutorizacionInsuficienteFailure`, `MaxSuperadminsFailure`, `AutoeliminacionFailure`, `TokenInvalidoFailure`
    - Implementar `lib/core/utils/validators.dart`: `validarEmail(String)` y `validarPassword(String)` (longitud ≥ 8)
    - _Requirements: 1.5, 1.6, 9.6_
    - _Design: Error Handling_

  - [x] 1.5 Cablear el punto de entrada y el shell de la app
    - Implementar `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, `initSupabase()`, envolver la app en `ProviderScope`
    - Implementar `lib/app.dart`: `MaterialApp` con tema (`lib/core/theme`) y el shell de enrutado
    - Implementar `lib/core/router/app_router.dart`: rutas base y guarda de sesión que escucha `supabase.auth.onAuthStateChange` (público vs. autenticado)
    - _Requirements: 7.3_
    - _Design: Flujo de autenticación y sesión; core/router_

- [x] 2. Esquema de base de datos: migraciones base (tablas, constraints, trigger, RLS)
  - [x] 2.1 Crear la migración de tablas y constraints
    - Implementar `supabase/migrations/0001_schema.sql`
    - Tabla `profiles`: `id` PK/FK→`auth.users` ON DELETE CASCADE, `nombre`/`apellidos` NOT NULL, `foto_url` NULL, `email` NOT NULL UNIQUE, `saldo_clases` NOT NULL DEFAULT 10 `CHECK (saldo_clases BETWEEN 0 AND 10)`, `estado` DEFAULT 'activo' `CHECK (estado IN ('activo','suspendido'))`, `rol` DEFAULT 'usuario' `CHECK (rol IN ('usuario','superadmin'))`, `metadata jsonb` NOT NULL DEFAULT '{}', `created_at`
    - Tabla `clases`: `id` PK, `horario` NOT NULL, `aforo` NOT NULL `CHECK (aforo BETWEEN 1 AND 10)`, `monitor` NOT NULL, `created_by` FK→`profiles`, `created_at`
    - Tabla `reservas`: `id` PK, `clase_id` FK→`clases` ON DELETE CASCADE, `user_id` FK→`profiles` ON DELETE CASCADE, `status CHECK (status IN ('confirmada','espera'))`, `posicion` NULL, `created_at`, `UNIQUE (clase_id, user_id)`
    - _Requirements: 1.1, 1.2, 3.5, 4.4, 5.1, 8.1, 8.6, 8.10, 8.12_
    - _Design: Data Models (tablas profiles, clases, reservas)_

  - [x] 2.2 Crear el trigger de alta de perfil y el helper de rol
    - Implementar `supabase/migrations/0002_trigger_helper.sql`
    - Función + trigger `on_auth_user_created`: inserta fila en `public.profiles` con `saldo_clases = 10` y `estado = 'activo'` tomando `nombre`/`apellidos` de la metadata de signup
    - Función auxiliar `es_superadmin()` (`SECURITY DEFINER`) que devuelve si el `rol` del llamante (`auth.uid()`) es `'superadmin'`
    - _Requirements: 1.1, 1.2, 5.3_
    - _Design: Flujo de autenticación y sesión; Security and RLS Strategy_

  - [x] 2.3 Crear el esqueleto de políticas RLS
    - Implementar `supabase/migrations/0003_rls.sql`
    - Activar RLS en `profiles`, `clases`, `reservas`; sin políticas para `anon` sobre datos de usuario
    - `profiles` SELECT `USING (auth.uid() = id OR es_superadmin())`; UPDATE con `WITH CHECK` que solo permite modificar `nombre`, `apellidos`, `foto_url`, `metadata`
    - `clases` SELECT para autenticados; INSERT/UPDATE/DELETE solo si `es_superadmin()`
    - `reservas` SELECT/INSERT/DELETE solo filas propias (`auth.uid() = user_id`)
    - _Requirements: 3.3, 3.4, 7.2, 7.3, 8.1, 8.2_
    - _Design: Security and RLS Strategy_

- [x] 3. Checkpoint - Esqueleto compilable
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Modelo de dominio puro del bono y reservas (espejo de las RPC)
  - [x] 4.1 Implementar entidades de dominio compartidas
    - En `lib/features/*/domain/entities/`: `AppUser`/`Profile` (incluye `saldoClases`, `estado`, `rol`, `metadata`), `Clase`, `Reserva` (con `status`, `posicion`), `ReservaResult`
    - _Requirements: 3.1, 3.5, 8.1_
    - _Design: Data Models; Servicios de dominio_

  - [x] 4.2 Implementar el modelo de bono puro
    - En `lib/features/bono/domain/`: funciones puras `consumir(saldo)`, `reembolsar(saldo)`, `ajustar(saldo, valor)`, `restablecer()`, con clamp estricto al rango 0..10
    - _Requirements: 4.2, 4.3, 4.4, 6.5, 6.6, 8.10_
    - _Design: Servicio_Bono; Funciones RPC del backend_

  - [ ]* 4.3 Prueba de propiedad: invariante del saldo 0..10
    - **Property 2: La invariante del saldo se mantiene en 0..10**
    - Trazabilidad: `Feature: gym-management-app, Property 2`
    - **Validates: Requirements 4.4, 8.10**

  - [ ]* 4.4 Prueba de propiedad: el consumo decrementa exactamente en 1
    - **Property 11: El consumo de bono decrementa exactamente en 1**
    - Trazabilidad: `Feature: gym-management-app, Property 11`
    - **Validates: Requirements 4.2**

  - [ ]* 4.5 Prueba de propiedad: restablecer el bono fija el saldo en 10
    - **Property 16: Restablecer el bono fija el saldo en 10**
    - Trazabilidad: `Feature: gym-management-app, Property 16`
    - **Validates: Requirements 6.5**

  - [ ]* 4.6 Prueba de propiedad: ajustar fija el valor y rechaza fuera de rango
    - **Property 17: Ajustar el saldo fija el valor solicitado y rechaza fuera de rango**
    - Trazabilidad: `Feature: gym-management-app, Property 17`
    - **Validates: Requirements 6.6**

  - [x] 4.7 Implementar el modelo puro de reservas, lista de espera y promoción
    - En `lib/features/reservas/domain/`: modelo en memoria con operaciones `reservar(estado, usuario)`, `cancelar(estado, usuario, antelacionHoras)` y promoción FIFO; refleja aforo, lista de espera (máx. 20), duplicados, reembolso según antelación ≥ 2h y promoción del primero con saldo > 0
    - _Requirements: 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.11, 8.12_
    - _Design: Funciones RPC del backend; Tabla reservas_

  - [ ]* 4.8 Prueba de propiedad: reserva con plaza libre crea confirmada y descuenta 1
    - **Property 23: Reserva con plaza libre crea confirmada y descuenta exactamente 1**
    - Trazabilidad: `Feature: gym-management-app, Property 23`
    - **Validates: Requirements 8.3**

  - [ ]* 4.9 Prueba de propiedad: clase llena añade al final de la espera sin tocar saldo
    - **Property 24: Reserva en clase llena añade al final de la lista de espera sin tocar el saldo**
    - Trazabilidad: `Feature: gym-management-app, Property 24`
    - **Validates: Requirements 8.5**

  - [ ]* 4.10 Prueba de propiedad: no se permiten reservas/entradas duplicadas
    - **Property 25: No se permiten reservas ni entradas de espera duplicadas**
    - Trazabilidad: `Feature: gym-management-app, Property 25`
    - **Validates: Requirements 8.6**

  - [ ]* 4.11 Prueba de propiedad: reembolso al cancelar si y solo si antelación ≥ 2h
    - **Property 26: El reembolso al cancelar ocurre si y solo si la antelación es ≥ 2 horas**
    - Trazabilidad: `Feature: gym-management-app, Property 26`
    - **Validates: Requirements 8.7, 8.8**

  - [ ]* 4.12 Prueba de propiedad: promoción del primero de la espera con saldo > 0 y descuento 1
    - **Property 27: Al liberarse una plaza se promociona al primero de la espera con saldo > 0 y se descuenta 1**
    - Trazabilidad: `Feature: gym-management-app, Property 27`
    - **Validates: Requirements 8.9**

  - [ ]* 4.13 Prueba de propiedad: cancelar estando en espera no afecta al saldo
    - **Property 28: Cancelar estando en lista de espera no afecta al saldo**
    - Trazabilidad: `Feature: gym-management-app, Property 28`
    - **Validates: Requirements 8.11**

  - [ ]* 4.14 Prueba de propiedad: rechazo por saldo cero y por lista de espera llena
    - **Property 30: Rechazo de reserva por saldo cero y por lista de espera llena (casos borde)**
    - Trazabilidad: `Feature: gym-management-app, Property 30`
    - **Validates: Requirements 4.3, 8.4, 8.12**

- [x] 5. Checkpoint - Modelo de dominio verificado
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Feature Auth: registro, login/logout y recuperación de contraseña
  - [x] 6.1 Definir el contrato e implementar el data source de autenticación
    - En `lib/features/auth/domain/repositories/auth_repository.dart`: interfaz `AuthRepository` (`signUp`, `signIn`, `signOut`, `requestPasswordReset`, `updatePasswordWithToken`, `authStateChanges`)
    - En `lib/features/auth/data/datasources/auth_remote_datasource.dart`: llamadas a Supabase Auth (`signUp` con metadata nombre/apellidos, `signInWithPassword`, `signOut`, `resetPasswordForEmail`, `updateUser`)
    - _Requirements: 1.1, 1.3, 2.1, 2.4, 2.5, 7.1, 9.2, 9.7_
    - _Design: Servicio_Autenticacion_

  - [x] 6.2 Implementar `AuthRepositoryImpl` con validación y traducción de errores
    - Validar email (Req 1.5) y longitud de contraseña (Req 1.6/9.6) antes de llamar a Auth
    - Traducir `AuthException` a `EmailEnUsoFailure`, `CredencialesInvalidasFailure`, `CuentaSuspendidaFailure`, `TokenInvalidoFailure`
    - `requestPasswordReset` devuelve siempre el mismo mensaje genérico (Req 9.1)
    - Subir foto a Storage (`avatars`) si se proporciona y asociar `foto_url` (Req 1.7)
    - _Requirements: 1.4, 1.5, 1.6, 1.7, 2.2, 2.3, 9.1, 9.6, 9.10_
    - _Design: Servicio_Autenticacion; Error Handling; Supabase Storage_

  - [ ]* 6.3 Prueba de propiedad: inicialización de bono y estado al registrarse
    - **Property 1: Inicialización del bono y estado al registrarse**
    - Trazabilidad: `Feature: gym-management-app, Property 1`
    - **Validates: Requirements 1.1, 1.2**

  - [ ]* 6.4 Prueba de propiedad: las contraseñas nunca se almacenan/comparan en texto plano
    - **Property 3: Las contraseñas nunca se almacenan ni comparan en texto plano**
    - Trazabilidad: `Feature: gym-management-app, Property 3`
    - **Validates: Requirements 1.3, 2.5, 7.1, 9.7**

  - [ ]* 6.5 Prueba de propiedad: el email duplicado se rechaza
    - **Property 4: El email duplicado se rechaza**
    - Trazabilidad: `Feature: gym-management-app, Property 4`
    - **Validates: Requirements 1.4**

  - [ ]* 6.6 Prueba de propiedad: el formato de email inválido se rechaza
    - **Property 5: El formato de email inválido se rechaza**
    - Trazabilidad: `Feature: gym-management-app, Property 5`
    - **Validates: Requirements 1.5**

  - [ ]* 6.7 Prueba de propiedad: la contraseña demasiado corta se rechaza
    - **Property 6: La contraseña demasiado corta se rechaza**
    - Trazabilidad: `Feature: gym-management-app, Property 6`
    - **Validates: Requirements 1.6, 9.6**

  - [ ]* 6.8 Prueba de propiedad: el usuario suspendido no inicia sesión ni restablece contraseña
    - **Property 7: El usuario suspendido no puede iniciar sesión ni restablecer su contraseña**
    - Trazabilidad: `Feature: gym-management-app, Property 7`
    - **Validates: Requirements 2.3, 9.10**

  - [ ]* 6.9 Prueba de propiedad: la solicitud de restablecimiento devuelve mensaje genérico
    - **Property 29: La solicitud de restablecimiento devuelve siempre un mensaje genérico**
    - Trazabilidad: `Feature: gym-management-app, Property 29`
    - **Validates: Requirements 9.1**

  - [x] 6.10 Implementar providers y pantallas de autenticación
    - En `lib/features/auth/presentation/providers/auth_providers.dart`: `AsyncNotifier` que orquesta signUp/signIn/signOut/reset y expone estados carga/éxito/error
    - Pantallas `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`
    - Cablear el enrutado de sesión del paso 1.5 a estos providers
    - _Requirements: 2.1, 2.4, 9.1, 9.6_
    - _Design: Capas del cliente Flutter; presentation/screens_

  - [ ]* 6.11 Pruebas unitarias de flujos de autenticación
    - Login correcto establece sesión (2.1), logout finaliza sesión (2.4), asociación de foto en registro (1.7)
    - _Requirements: 1.7, 2.1, 2.4_

- [x] 7. Feature Profile: consulta y actualización de perfil
  - [x] 7.1 Implementar `ProfileRepository` y su data source
    - Interfaz `getMyProfile()` / `updateMyProfile(...)` y la implementación con Supabase (`select`/`update` sobre `profiles`, subida de foto a Storage)
    - No exponer modificación de `saldo_clases` ni `estado` (reforzado por RLS del paso 2.3)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
    - _Design: Servicio_Usuarios_

  - [ ]* 7.2 Prueba de propiedad: round trip de actualización de perfil
    - **Property 8: Round trip de actualización de perfil**
    - Trazabilidad: `Feature: gym-management-app, Property 8`
    - **Validates: Requirements 3.2**

  - [ ]* 7.3 Prueba de propiedad: el usuario estándar no puede modificar saldo ni estado
    - **Property 9: El usuario estándar no puede modificar su saldo ni su estado**
    - Trazabilidad: `Feature: gym-management-app, Property 9`
    - **Validates: Requirements 3.3, 3.4**

  - [ ]* 7.4 Prueba de propiedad: el modelo de usuario es ampliable (round trip de metadata)
    - **Property 10: El modelo de usuario es ampliable (preservación de metadata)**
    - Trazabilidad: `Feature: gym-management-app, Property 10`
    - **Validates: Requirements 3.5**

  - [x] 7.5 Implementar providers y pantalla de perfil
    - Provider de perfil (`FutureProvider`/`AsyncNotifier`) y `profile_screen.dart` con edición de nombre/apellidos/foto y lectura de saldo
    - _Requirements: 3.1, 3.2_
    - _Design: Capas del cliente Flutter_

- [x] 8. Feature Bono: consulta de saldo y RPC de bono
  - [x] 8.1 Implementar `BonoRepository.getSaldo()` y la RPC `restablecer_bono`
    - Repositorio que lee el saldo vía `select`; migración `supabase/migrations/0004_rpc_bono.sql` con `restablecer_bono(user_id)` (`SECURITY DEFINER`, valida superadmin, fija 10) y `ajustar_bono(user_id, valor)` (valida superadmin y `0 ≤ valor ≤ 10`)
    - _Requirements: 4.1, 6.5, 6.6_
    - _Design: Servicio_Bono; Funciones RPC del backend_

  - [ ]* 8.2 Pruebas unitarias de lectura de saldo y RPC de bono
    - Lectura de saldo (4.1); `restablecer_bono` fija 10 y `ajustar_bono` fija valor / rechaza fuera de rango vía RPC real
    - _Requirements: 4.1, 6.5, 6.6_

- [~] 9. Checkpoint - Auth, perfil y bono integrados
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Feature Admin: gestión de usuarios y superadministradores
  - [x] 10.1 Implementar las RPC administrativas
    - Migración `supabase/migrations/0005_rpc_admin.sql`: `suspender_usuario`, `reactivar_usuario`, `eliminar_usuario` (rechaza autoeliminación de superadmin), `conceder_superadmin` (bloqueo `FOR UPDATE` + conteo < 2); todas validan `es_superadmin()`
    - _Requirements: 5.1, 5.2, 5.4, 6.2, 6.3, 6.4, 6.7_
    - _Design: Funciones RPC del backend; invariante de máximo 2 superadmins_

  - [x] 10.2 Implementar `AdminRepository` y su data source
    - `listUsers`, `suspendUser`, `reactivateUser`, `deleteUser`, `restablecerBono`, `ajustarBono`, `grantSuperadmin` sobre las RPC; traducción de errores a `MaxSuperadminsFailure`, `AutoeliminacionFailure`, `AutorizacionInsuficienteFailure`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 5.2, 5.4, 6.7_
    - _Design: Servicio_Administracion; Error Handling_

  - [ ]* 10.3 Prueba de propiedad: como máximo dos superadministradores
    - **Property 12: Como máximo dos superadministradores**
    - Trazabilidad: `Feature: gym-management-app, Property 12`
    - **Validates: Requirements 5.1, 5.2**

  - [ ]* 10.4 Prueba de propiedad: el usuario estándar es denegado en gestión
    - **Property 13: El usuario estándar es denegado en operaciones de gestión**
    - Trazabilidad: `Feature: gym-management-app, Property 13`
    - **Validates: Requirements 5.4**

  - [ ]* 10.5 Prueba de propiedad: suspender y reactivar (round trip de estado)
    - **Property 14: Suspender y reactivar (round trip de estado)**
    - Trazabilidad: `Feature: gym-management-app, Property 14`
    - **Validates: Requirements 6.2, 6.3**

  - [ ]* 10.6 Prueba de propiedad: la eliminación borra el registro
    - **Property 15: La eliminación de un usuario borra su registro**
    - Trazabilidad: `Feature: gym-management-app, Property 15`
    - **Validates: Requirements 6.4**

  - [ ]* 10.7 Prueba de propiedad: un superadministrador no puede autoeliminarse
    - **Property 18: Un superadministrador no puede autoeliminarse**
    - Trazabilidad: `Feature: gym-management-app, Property 18`
    - **Validates: Requirements 6.7**

  - [~] 10.8 Implementar providers y panel de administración
    - Provider de administración y pantallas de listado/gestión de usuarios (suspender, reactivar, eliminar, ajustar/restablecer bono, conceder superadmin)
    - _Requirements: 5.3, 6.1_
    - _Design: Capas del cliente Flutter_

  - [ ]* 10.9 Pruebas unitarias de acceso de superadmin
    - Acceso de superadmin a gestión (5.3) y listado de usuarios (6.1)
    - _Requirements: 5.3, 6.1_

- [ ] 11. Feature Reservas: calendario, aforo y lista de espera
  - [x] 11.1 Implementar las RPC transaccionales de reservas
    - Migración `supabase/migrations/0006_rpc_reservas.sql`: `reservar_clase(clase_id)` (valida saldo > 0, aforo, duplicados, lista de espera < 20, decremento atómico) y `cancelar_reserva(clase_id)` (libera plaza, reembolso si ≥ 2h, promoción FIFO del primero con saldo > 0 dentro de la transacción, o elimina entrada de espera sin tocar saldo)
    - _Requirements: 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.11, 8.12_
    - _Design: Funciones RPC del backend_

  - [x] 11.2 Implementar `ReservasRepository`, data source y CRUD de clases
    - `getCalendario`, `crearClase`, `editarClase`, `eliminarClase` (solo superadmin, vía RLS/validación), `reservar` y `cancelar` (vía RPC); traducción de errores a `SinClasesFailure`, `ListaEsperaLlenaFailure`, `ReservaDuplicadaFailure`, `AutorizacionInsuficienteFailure`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.11, 8.12_
    - _Design: Servicio_Reservas; Error Handling_

  - [ ]* 11.3 Prueba de propiedad: el aforo está en el rango 1..10
    - **Property 21: El aforo de una clase está en el rango 1..10**
    - Trazabilidad: `Feature: gym-management-app, Property 21`
    - **Validates: Requirements 8.1**

  - [ ]* 11.4 Prueba de propiedad: el usuario estándar no puede modificar clases
    - **Property 22: El usuario estándar no puede modificar clases**
    - Trazabilidad: `Feature: gym-management-app, Property 22`
    - **Validates: Requirements 8.2**

  - [~] 11.5 Implementar providers y pantallas de calendario/reserva
    - Provider de reservas y pantallas de calendario (vista de clases, reservar, cancelar, estado de lista de espera) y gestión de clases para superadmin
    - _Requirements: 8.1, 8.3, 8.5, 8.7, 8.11_
    - _Design: Capas del cliente Flutter_

  - [ ]* 11.6 Pruebas de integración de las RPC de reservas vs. el modelo de dominio
    - Verificar que `reservar_clase`/`cancelar_reserva` reales coinciden con el modelo puro, incluida la condición de carrera por la última plaza
    - _Requirements: 8.3, 8.5, 8.9, 8.12_
    - _Design: Testing Strategy (pruebas de integración)_

- [ ] 12. Integración de seguridad y recuperación de contraseña (Supabase Auth/RLS)
  - [ ]* 12.1 Prueba de propiedad: un usuario solo accede a sus propios datos (salvo superadmin)
    - **Property 19: Un usuario solo accede a sus propios datos (salvo superadmin)**
    - Trazabilidad: `Feature: gym-management-app, Property 19`
    - **Validates: Requirements 7.2**

  - [ ]* 12.2 Prueba de propiedad: sin sesión no hay acceso a datos de usuario
    - **Property 20: Sin sesión no hay acceso a datos de usuario**
    - Trazabilidad: `Feature: gym-management-app, Property 20`
    - **Validates: Requirements 7.3**

  - [ ]* 12.3 Pruebas de integración de RLS y del flujo de restablecimiento
    - RLS deniega acceso anónimo y cruzado contra Supabase local (refuerzo de Property 19 y 20)
    - Envío del enlace (9.2), caducidad a 60 min (9.3), token caducado (9.4), token usado (9.5/9.9), invalidación de sesiones tras reset (9.8)
    - _Requirements: 7.2, 7.3, 9.2, 9.3, 9.4, 9.5, 9.8, 9.9_
    - _Design: Testing Strategy (pruebas de integración)_

- [~] 13. Checkpoint final - Todas las features y pruebas integradas
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Las tareas marcadas con `*` son opcionales (pruebas) y pueden omitirse para un MVP más rápido; las tareas de implementación nunca van marcadas como opcionales.
- El esqueleto del proyecto (grupo 1) y las migraciones base (grupo 2) van primero; todo lo demás se construye encima.
- La lógica de bono/reservas se valida como funciones puras de dominio con `glados` (mínimo 100 iteraciones por propiedad); las RPC reales se verifican con pruebas de integración.
- Cada prueba de propiedad referencia una única propiedad del diseño con la etiqueta de trazabilidad `Feature: gym-management-app, Property N`.
- Los requisitos gestionados por Supabase Auth (tokens de restablecimiento, caducidad, un solo uso) se verifican con pruebas de integración, no con PBT.
- Los checkpoints aseguran validación incremental en los cortes naturales del plan.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3", "1.4", "2.1"] },
    { "id": 3, "tasks": ["1.5", "2.2", "4.1"] },
    { "id": 4, "tasks": ["2.3", "4.2", "4.7", "6.1", "7.1"] },
    { "id": 5, "tasks": ["4.3", "4.4", "4.5", "4.6", "4.8", "4.9", "4.10", "4.11", "4.12", "4.13", "4.14", "6.2", "7.2", "7.3", "7.4", "7.5", "8.1"] },
    { "id": 6, "tasks": ["6.3", "6.4", "6.5", "6.6", "6.7", "6.8", "6.9", "6.10", "8.2", "10.1", "11.1"] },
    { "id": 7, "tasks": ["6.11", "10.2", "11.2"] },
    { "id": 8, "tasks": ["10.3", "10.4", "10.5", "10.6", "10.7", "10.8", "11.3", "11.4", "11.5"] },
    { "id": 9, "tasks": ["10.9", "11.6", "12.1", "12.2", "12.3"] }
  ]
}
```
