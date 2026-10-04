-- Migration: 0007_entrenamiento_dia.sql
-- Feature: gym-management-app (Olympus)
-- Crea la tabla del plan de entrenamiento del dia (comun a todas las franjas
-- horarias de esa fecha) y sus politicas RLS. El plan es una lista ordenada de
-- actividades (p. ej. "Calentamiento", "Fuerza") que se muestra en la pantalla
-- del calendario encima de las franjas horarias (clases) de ese dia.
--   * Lectura: cualquier Usuario autenticado puede consultar el plan del dia
--     (mismo criterio que la lectura del calendario de clases).
--   * Escritura (INSERT/UPDATE/DELETE): solo superadministradores, reforzado por
--     RLS con es_superadmin() (migracion 0002), igual que el CRUD de clases.
-- Esta migracion es aditiva: NO modifica tablas, triggers ni politicas previos
-- (0001-0006). Solo crea una tabla nueva y sus politicas.
-- _Requirements: 8.1, 8.2, 7.3_
-- _Design: Capas del cliente Flutter; Servicio_Reservas

-- =====================================================================
-- Tabla entrenamiento_dia
-- Una fila por fecha (unica). `actividades` es un array de texto ordenado con
-- las actividades del dia. `fecha` es la clave natural usada por el cliente
-- para asociar el plan con las clases cuyo horario cae en ese dia.
-- =====================================================================
create table if not exists public.entrenamiento_dia (
    id          uuid        primary key default gen_random_uuid(),
    fecha       date        not null unique,
    actividades text[]      not null default '{}',
    created_by  uuid        references public.profiles (id),
    created_at  timestamptz not null default now()
);

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.entrenamiento_dia enable row level security;

-- SELECT: cualquier usuario autenticado puede consultar el plan del dia.
drop policy if exists entrenamiento_dia_select_autenticados on public.entrenamiento_dia;
create policy entrenamiento_dia_select_autenticados
    on public.entrenamiento_dia
    for select
    to authenticated
    using (true);

-- INSERT/UPDATE/DELETE: solo superadministradores (Req 8.2).
drop policy if exists entrenamiento_dia_insert_admin on public.entrenamiento_dia;
create policy entrenamiento_dia_insert_admin
    on public.entrenamiento_dia
    for insert
    to authenticated
    with check (public.es_superadmin());

drop policy if exists entrenamiento_dia_update_admin on public.entrenamiento_dia;
create policy entrenamiento_dia_update_admin
    on public.entrenamiento_dia
    for update
    to authenticated
    using (public.es_superadmin())
    with check (public.es_superadmin());

drop policy if exists entrenamiento_dia_delete_admin on public.entrenamiento_dia;
create policy entrenamiento_dia_delete_admin
    on public.entrenamiento_dia
    for delete
    to authenticated
    using (public.es_superadmin());
