-- Migration: 0011_reservas_select_superadmin.sql
-- Feature: gym-management-app (Olympus)
--
-- Corrige la política SELECT de `reservas` para que un superadministrador pueda
-- ver las reservas de TODOS los usuarios (lista de apuntados de una clase),
-- igual que ya ocurre con `profiles` (migración 0003, `auth.uid() = id OR
-- es_superadmin()`).
--
-- Problema: la política original `reservas_select_propias` usaba
-- `using (auth.uid() = user_id)` sin excepción para el superadmin. Al desplegar
-- la lista de apuntados de una clase desde el panel de administración
-- (`fetchApuntados`, que lee la tabla `reservas` directamente), RLS ocultaba
-- todas las filas ajenas y mostraba "nadie se ha apuntado", aunque la ocupación
-- (calculada por la RPC `ocupacion_clase`, SECURITY DEFINER) sí reflejara 1/10.
--
-- Solución: añadir la rama `OR es_superadmin()` a la política SELECT. Un usuario
-- estándar sigue viendo solo sus propias reservas (Req 7.2); el superadmin ve
-- todas (Req 6.1, 8.2). Las políticas de INSERT/DELETE no cambian: cada usuario
-- sigue creando/borrando solo las suyas, y las mutaciones con invariantes pasan
-- por las RPC SECURITY DEFINER.
--
-- Migración aditiva: solo redefine la política SELECT de `reservas`.
-- _Requirements: 6.1, 7.2, 8.2_
-- _Design: Security and RLS Strategy_

drop policy if exists reservas_select_propias on public.reservas;
create policy reservas_select_propias
    on public.reservas
    for select
    to authenticated
    using (auth.uid() = user_id or public.es_superadmin());
