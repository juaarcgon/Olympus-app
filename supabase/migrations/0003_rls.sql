-- Migration: 0003_rls.sql
-- Feature: gym-management-app (Olympus)
-- Activa Row Level Security (RLS) y define el esqueleto de politicas de acceso
-- sobre profiles, clases y reservas. Implementa la "Security and RLS Strategy"
-- del diseno: defensa en profundidad en la capa de base de datos.
--   * Sin sesion no hay datos: RLS activado y ninguna politica para el rol anon
--     sobre datos de usuario (Req 7.3).
--   * Un usuario solo ve lo suyo; el superadmin ve todo (Req 7.2).
--   * El usuario estandar no puede modificar saldo_clases/estado/rol; esas
--     columnas solo cambian via funciones SECURITY DEFINER. La inmutabilidad a
--     nivel de columna se refuerza con un trigger BEFORE UPDATE porque WITH CHECK
--     no puede comparar con la fila anterior (OLD) (Req 3.3, 3.4).
--   * Clases: lectura para autenticados; escritura solo para superadmin
--     (Req 8.1, 8.2).
--   * Reservas: cada usuario ve/crea/borra solo sus propias filas; la mutacion
--     real con invariantes pasa por RPC.
-- _Requirements: 3.3, 3.4, 7.2, 7.3, 8.1, 8.2_
-- _Design: Security and RLS Strategy_

-- =====================================================================
-- Activacion de RLS en todas las tablas de datos de usuario.
-- Al activar RLS sin politicas, el acceso queda denegado por defecto; cada
-- politica declarada mas abajo abre un camino concreto y acotado. El rol anon
-- (clientes sin JWT) no recibe ninguna politica, de modo que no obtiene filas
-- (Req 7.3).
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.clases   enable row level security;
alter table public.reservas enable row level security;

-- =====================================================================
-- Politicas de profiles
-- =====================================================================

-- SELECT: un usuario autenticado solo ve su propia fila; un superadmin ve
-- todas las filas. es_superadmin() es SECURITY DEFINER, por lo que la propia
-- consulta de rol no queda bloqueada por esta misma politica (Req 7.2).
drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin
    on public.profiles
    for select
    to authenticated
    using (auth.uid() = id or public.es_superadmin());

-- UPDATE: un usuario autenticado solo puede actuar sobre su propia fila.
-- La restriccion de QUE columnas puede cambiar (solo nombre, apellidos,
-- foto_url, metadata) se refuerza con el trigger de inmutabilidad declarado
-- mas abajo, ya que WITH CHECK no puede comparar contra los valores previos
-- (OLD) de la fila (Req 3.3, 3.4).
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
    on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- ---------------------------------------------------------------------
-- Trigger de inmutabilidad de columnas sensibles en profiles.
-- Impide que un usuario estandar modifique saldo_clases, estado o rol en un
-- UPDATE directo. Las funciones administrativas y de reservas que si deben
-- cambiar estas columnas son SECURITY DEFINER y corren como el propietario
-- de la funcion (no 'authenticated'), por lo que no disparan este rechazo.
-- Se permite el cambio cuando el llamante es superadmin (consistencia con las
-- RPC administrativas) o cuando el rol de sesion no es 'authenticated'
-- (contexto SECURITY DEFINER / superusuario).
-- Refuerza Req 3.3 (saldo) y 3.4 (estado); protege ademas rol (Req 5).
-- ---------------------------------------------------------------------
create or replace function public.profiles_proteger_columnas()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Contexto privilegiado (RPC SECURITY DEFINER, superusuario, servicio):
    -- se permite cualquier cambio. Solo restringimos al rol 'authenticated'
    -- (el cliente con JWT de usuario).
    if current_setting('role', true) is distinct from 'authenticated'
       and current_user <> 'authenticated' then
        return new;
    end if;

    -- Un superadmin puede cambiar estas columnas (consistencia con las
    -- operaciones de gestion); el usuario estandar no.
    if public.es_superadmin() then
        return new;
    end if;

    if new.saldo_clases is distinct from old.saldo_clases then
        raise exception 'No autorizado: el saldo de clases solo se modifica mediante operaciones del sistema'
            using errcode = '42501';
    end if;

    if new.estado is distinct from old.estado then
        raise exception 'No autorizado: el estado de la cuenta solo lo modifica un superadministrador'
            using errcode = '42501';
    end if;

    if new.rol is distinct from old.rol then
        raise exception 'No autorizado: el rol solo lo modifica un superadministrador'
            using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists profiles_inmutabilidad_columnas on public.profiles;

create trigger profiles_inmutabilidad_columnas
    before update on public.profiles
    for each row
    execute function public.profiles_proteger_columnas();

-- =====================================================================
-- Politicas de clases
-- =====================================================================

-- SELECT: cualquier usuario autenticado puede consultar el calendario.
drop policy if exists clases_select_autenticados on public.clases;
create policy clases_select_autenticados
    on public.clases
    for select
    to authenticated
    using (true);

-- INSERT/UPDATE/DELETE: solo los superadministradores pueden crear, editar o
-- eliminar clases del calendario (Req 8.1, 8.2).
drop policy if exists clases_insert_admin on public.clases;
create policy clases_insert_admin
    on public.clases
    for insert
    to authenticated
    with check (public.es_superadmin());

drop policy if exists clases_update_admin on public.clases;
create policy clases_update_admin
    on public.clases
    for update
    to authenticated
    using (public.es_superadmin())
    with check (public.es_superadmin());

drop policy if exists clases_delete_admin on public.clases;
create policy clases_delete_admin
    on public.clases
    for delete
    to authenticated
    using (public.es_superadmin());

-- =====================================================================
-- Politicas de reservas
-- Un usuario solo ve, crea y borra sus propias filas. La mutacion con
-- invariantes (aforo, lista de espera, bono) se realiza mediante RPC
-- SECURITY DEFINER; estas politicas cubren el acceso directo del cliente.
-- No se declara politica de UPDATE: los cambios de estado/posicion de una
-- reserva (promocion desde lista de espera) solo ocurren dentro de las RPC.
-- =====================================================================
drop policy if exists reservas_select_propias on public.reservas;
create policy reservas_select_propias
    on public.reservas
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists reservas_insert_propias on public.reservas;
create policy reservas_insert_propias
    on public.reservas
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists reservas_delete_propias on public.reservas;
create policy reservas_delete_propias
    on public.reservas
    for delete
    to authenticated
    using (auth.uid() = user_id);
