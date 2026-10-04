-- Migration: 0005_rpc_admin.sql
-- Feature: gym-management-app (Olympus)
-- Funciones RPC transaccionales para la gestion de Usuarios por un superadmin
-- (Servicio_Administracion). Toda operacion valida es_superadmin() en el
-- backend, de modo que la autorizacion critica ocurre aqui aunque el cliente la
-- omita (Req 5.4).
--   * suspender_usuario(target_user_id): da de baja (estado='suspendido') (Req 6.2).
--   * reactivar_usuario(target_user_id): reactiva (estado='activo') (Req 6.3).
--   * eliminar_usuario(target_user_id): elimina el registro del Usuario (Req 6.4);
--     rechaza la autoeliminacion del superadmin que llama (Req 6.7).
--   * conceder_superadmin(target_user_id): asigna rol 'superadmin' respetando el
--     maximo de dos (2) superadministradores; usa bloqueo FOR UPDATE para evitar
--     carreras que superen la invariante (Req 5.1, 5.2).
-- Todas son SECURITY DEFINER con search_path fijo y usan RAISE EXCEPTION USING
-- ERRCODE/MESSAGE para senalar condiciones de negocio, acorde a la estrategia de
-- Error Handling del diseno.
-- _Requirements: 5.1, 5.2, 5.4, 6.2, 6.3, 6.4, 6.7_
-- _Design: Funciones RPC del backend; invariante de maximo 2 superadmins_

-- =====================================================================
-- Funcion: suspender_usuario(target_user_id)
-- Valida que el llamante sea superadmin y fija el Estado_Usuario del Usuario
-- objetivo en 'suspendido' (dar de baja) (Req 6.2). Rechaza con error de
-- autorizacion insuficiente si el llamante no es superadmin (Req 5.4).
-- SECURITY DEFINER + search_path fijo: la escritura corre con los privilegios
-- del propietario y evita que la RLS o un search_path manipulado alteren el
-- comportamiento.
-- =====================================================================
create or replace function public.suspender_usuario(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Autorizacion: solo un superadministrador puede dar de baja (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Fija el estado en 'suspendido' para el usuario objetivo (Req 6.2).
    update public.profiles
       set estado = 'suspendido'
     where id = target_user_id;

    -- Si el usuario objetivo no existe, se informa como dato no encontrado.
    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- Funcion: reactivar_usuario(target_user_id)
-- Valida que el llamante sea superadmin y fija el Estado_Usuario del Usuario
-- objetivo en 'activo' (Req 6.3). Rechaza sin autorizacion (Req 5.4).
-- =====================================================================
create or replace function public.reactivar_usuario(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Autorizacion: solo un superadministrador puede reactivar (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Fija el estado en 'activo' para el usuario objetivo (Req 6.3).
    update public.profiles
       set estado = 'activo'
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- Funcion: eliminar_usuario(target_user_id)
-- Valida que el llamante sea superadmin y elimina el registro del Usuario
-- objetivo (Req 6.4). Rechaza la autoeliminacion: un superadministrador no
-- puede eliminarse a si mismo (Req 6.7).
-- NOTA sobre el alcance: esta funcion elimina la fila de public.profiles. La
-- FK profiles.id -> auth.users(id) es ON DELETE CASCADE en sentido inverso
-- (al borrar la cuenta Auth se borra el perfil), y reservas.user_id ->
-- profiles.id es ON DELETE CASCADE, de modo que al eliminar el perfil se
-- eliminan en cascada sus reservas (el registro deja de existir, Req 6.4).
-- Limitacion conocida: eliminar la cuenta subyacente en auth.users requiere
-- privilegios de administracion de Supabase Auth (service_role / Admin API) y
-- no puede realizarse de forma segura desde esta RPC ejecutada por el rol
-- authenticated; la baja de la cuenta Auth debe realizarse por el canal
-- administrativo correspondiente.
-- =====================================================================
create or replace function public.eliminar_usuario(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Autorizacion: solo un superadministrador puede eliminar (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Rechaza la autoeliminacion: un superadministrador no puede eliminarse a
    -- si mismo (Req 6.7).
    if target_user_id = auth.uid() then
        raise exception 'Un superadministrador no puede eliminarse a si mismo'
            using errcode = '42501';
    end if;

    -- Elimina el registro del usuario objetivo; las reservas asociadas se
    -- borran en cascada (Req 6.4).
    delete from public.profiles
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- Funcion: conceder_superadmin(target_user_id)
-- Valida que el llamante sea superadmin y asigna el rol 'superadmin' al Usuario
-- objetivo, respetando el maximo de dos (2) superadministradores del Sistema
-- (Req 5.1, 5.2).
-- Control de concurrencia: antes de contar, se bloquean con FOR UPDATE las
-- filas actuales con rol 'superadmin'. Esto serializa dos concesiones
-- simultaneas, de modo que la segunda espera a que la primera confirme y ve el
-- conteo actualizado, evitando una carrera que supere el limite de 2.
-- =====================================================================
create or replace function public.conceder_superadmin(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    total_superadmins int;
    rol_objetivo      text;
begin
    -- Autorizacion: solo un superadministrador puede conceder el rol (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Comprueba que el usuario objetivo existe y, de paso, obtiene su rol
    -- actual bloqueando su fila para esta transaccion.
    select rol
      into rol_objetivo
      from public.profiles
     where id = target_user_id
       for update;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;

    -- Si el usuario objetivo ya es superadmin, no hay nada que hacer (idempotente)
    -- y no debe contar como una nueva concesion.
    if rol_objetivo = 'superadmin' then
        return;
    end if;

    -- Bloqueo FOR UPDATE sobre las filas de superadmins para serializar
    -- concesiones concurrentes antes de evaluar la invariante (Req 5.1).
    perform 1
       from public.profiles
      where rol = 'superadmin'
        for update;

    -- Cuenta los superadministradores actuales ya con las filas bloqueadas.
    select count(*)
      into total_superadmins
      from public.profiles
     where rol = 'superadmin';

    -- Invariante: maximo dos (2) superadministradores (Req 5.1, 5.2).
    if total_superadmins >= 2 then
        raise exception 'Se ha alcanzado el numero maximo de superadministradores'
            using errcode = 'P0001';
    end if;

    -- Asigna el rol de superadministrador al usuario objetivo.
    update public.profiles
       set rol = 'superadmin'
     where id = target_user_id;
end;
$$;

-- =====================================================================
-- Permisos de ejecucion
-- Se concede EXECUTE al rol authenticated; la autorizacion fina (superadmin)
-- se comprueba dentro del cuerpo de cada funcion. El rol anon no recibe
-- permiso: sin sesion no hay acceso (Req 7.3).
-- =====================================================================
grant execute on function public.suspender_usuario(uuid) to authenticated;
grant execute on function public.reactivar_usuario(uuid) to authenticated;
grant execute on function public.eliminar_usuario(uuid) to authenticated;
grant execute on function public.conceder_superadmin(uuid) to authenticated;
