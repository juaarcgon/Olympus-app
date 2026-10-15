# Pruebas de integración de seguridad (RLS) y restablecimiento (tarea 12.3)

Estas pruebas verifican, contra una **instancia real/local de Supabase**, el
comportamiento que el diseño delega en el backend (RLS en PostgreSQL y el flujo
de restablecimiento de Supabase Auth). Refuerzan en la base de datos real las
propiedades 19 y 20 (acceso a `profiles`) y cubren los requisitos de Auth que
**no** son aptos para PBT.

| Archivo | Cubre | Requisitos |
|---------|-------|------------|
| `rls_integracion_test.dart` | RLS deniega acceso anónimo y cruzado; permite propio y superadmin | 7.2, 7.3 |
| `restablecimiento_integracion_test.dart` | Envío de enlace, caducidad 60 min, token caducado, token usado, invalidación de sesiones | 9.2, 9.3, 9.4, 9.5, 9.8, 9.9 |
| `integration_config.dart` | Configuración compartida (`--dart-define`) y guarda de omisión | — |

## Omisión automática sin backend

Si no se proporcionan las variables de conexión, **todos** los grupos de
integración se marcan como `skip` (no fallan). Así `flutter test` sigue en verde
en CI y en entornos sin Supabase, y el código se analiza/compila igualmente con
`flutter analyze`.

## Ejecutar contra Supabase local

Requiere **Docker** (o Podman) para `supabase start`.

```bash
# 1) Levantar Supabase local y aplicar las migraciones de supabase/
supabase start
supabase db reset            # aplica supabase/migrations/*.sql

# 2) Anotar API URL, anon key y service role key:
supabase status

# 3) Ejecutar las pruebas de integración de seguridad
flutter test test/features/security/rls_integracion_test.dart \
             test/features/security/restablecimiento_integracion_test.dart \
  --dart-define=INTEGRATION_SUPABASE=true \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

### Variables (`--dart-define`)

- `INTEGRATION_SUPABASE=true` — interruptor maestro; sin él, se omiten.
- `SUPABASE_URL` — URL de la API (local: `http://127.0.0.1:54321`).
- `SUPABASE_ANON_KEY` — clave anónima/publishable.
- `SUPABASE_SERVICE_ROLE_KEY` — clave de servicio; **solo** para el arnés de
  pruebas (crear usuarios, fijar roles, leer sin RLS). Nunca se usa en la app.
- `RESET_TOKEN_EXPIRY_SECONDS` — (opcional) expiración esperada del token de
  restablecimiento; por defecto `3600` (60 min, Req 9.3).

## Notas sobre comportamientos gestionados por Supabase Auth

Algunos comportamientos los gobierna internamente Auth y no se pueden forzar de
forma determinista desde una prueba:

- **Caducidad a 60 min (9.3):** es un valor de configuración de Auth
  (`[auth.email] otp_expiry` en `supabase/config.toml`, o
  *Authentication → Email → Email OTP Expiration* en Cloud). La prueba afirma el
  valor esperado (3600 s); no "espera" 60 minutos.
- **Envío del email (9.2):** el envío real se inspecciona en **Inbucket/Mailpit**
  del stack local (`http://127.0.0.1:54324`). La prueba comprueba que la
  solicitud se acepta y que Auth emite un enlace con token.
- **Token caducado (9.4):** se valida el equivalente observable y forzable (un
  token inválido produce el mismo error "invalid or expired"); la expiración
  real se cubre manualmente.
- **Token usado (9.5/9.9)** e **invalidación de sesiones (9.8):** se fuerzan de
  forma determinista con la Admin API (`generateLink` + `verifyOTP`,
  `updateUser`, `refreshSession`).
