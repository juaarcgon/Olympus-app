-- Migration: 0002_trigger_helper.sql
-- Feature: gym-management-app (Olympus)
-- Crea el trigger de alta automatica de perfil y el helper de rol.
--   * handle_new_user() + trigger on_auth_user_created: al crear una fila en
--     auth.users (registro), inserta la fila espejo en public.profiles con
--     saldo_clases = 10 y estado = 'activo' (Req 1.1, 1.2).
--   * es_superadmin(): helper SECURITY DEFINER usado por las politicas RLS y las
--     RPC administrativas para comprobar si el llamante tiene rol 'superadmin'
--     (Req 5.3).
-- _Requirements: 1.1, 1.2, 5.3_
-- _Design: Flujo de autenticacion y sesion; Security and RLS Strategy_

-- =====================================================================
-- Funcion: handle_new_user()
-- Se ejecuta tras insertar una cuenta en auth.users. Crea la fila
-- correspondiente en public.profiles tomando nombre/apellidos de la
-- metadata del registro (raw_user_meta_data) y el email de la cuenta Auth.
-- SECURITY DEFINER: el trigger corre en el contexto de Supabase Auth, por lo
-- que necesita privilegios del propietario para escribir en public.profiles.
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.profiles (id, nombre, apellidos, email, saldo_clases, estado)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'nombre', ''),
        coalesce(new.raw_user_meta_data ->> 'apellidos', ''),
        new.email,
        10,         -- bono inicial completo (Req 1.2)
        'activo'    -- estado inicial (Req 1.1)
    );
    return new;
end;
$$;

-- Trigger: on_auth_user_created
-- AFTER INSERT en auth.users -> una fila nueva de perfil por cada registro.
drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- =====================================================================
-- Funcion: es_superadmin()
-- Devuelve true si el llamante actual (auth.uid()) tiene rol 'superadmin'
-- en public.profiles. Usada por las politicas RLS (SELECT/UPDATE/DELETE) y
-- por las RPC administrativas para reforzar la autorizacion (Req 5.3, 5.4).
-- SECURITY DEFINER + search_path fijo para evitar que RLS o un search_path
-- manipulado alteren el resultado.
-- =====================================================================
create or replace function public.es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.rol = 'superadmin'
    );
$$;
