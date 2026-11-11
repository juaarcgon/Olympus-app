-- Migration: 0017_eliminar_cuenta.sql
-- Feature: gym-management-app (Olympus)
--
-- Borrado de cuentas completo, exigido por Google Play (política de datos de
-- usuario: toda app con registro debe permitir eliminar la cuenta).
--
--   * `liberar_reservas_usuario(p_user)` (interna, sin permiso para clientes):
--     antes de borrar una cuenta, quita sus reservas y entradas de lista de
--     espera en clases que aún no han empezado y, si dejaba una plaza
--     confirmada, la pasa al primero de la lista de espera con saldo (FIFO),
--     igual que `cancelar_reserva`. El ascenso dispara el aviso push
--     (trigger de la migración 0015). Las reservas de clases ya empezadas se
--     borran en cascada con el perfil, sin ascensos.
--   * `eliminar_mi_cuenta()`: el Usuario de la sesión borra su propia cuenta.
--     Borra la fila de `auth.users`, lo que elimina en cascada el perfil, las
--     reservas, los móviles registrados y las sesiones. Un superadministrador
--     no puede borrarse a sí mismo desde la app.
--   * `eliminar_usuario(target_user_id)`: se redefine para borrar también la
--     cuenta de acceso (`auth.users`). Antes solo borraba el perfil y la cuenta
--     de acceso quedaba viva ("limitación conocida" de la migración 0005).
--   * Política de Storage `avatars_delete_superadmin`: el superadministrador
--     puede borrar la foto de perfil de otro Usuario al eliminarlo.
--
-- La foto de perfil NO se borra aquí: Supabase prohíbe borrar objetos de
-- Storage con SQL (trigger `storage.protect_delete`). La app la borra con la
-- API de Storage justo antes de llamar a estas funciones.
--
-- `clases.created_by` y `entrenamiento_dia.created_by` no tienen borrado en
-- cascada: se ponen a NULL para que las clases y planes que creó la cuenta no
-- impidan borrarla ni desaparezcan con ella.

-- =====================================================================
-- Interna: liberar las reservas futuras de un Usuario
-- =====================================================================
create or replace function public.liberar_reservas_usuario(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_clases       uuid[];
    v_clase        uuid;
    v_status       text;
    v_promocionado uuid;
    v_saldo        int;
begin
    -- El ascenso descuenta una clase al promocionado: marca la operación del
    -- sistema para el trigger de inmutabilidad del saldo (migración 0010).
    perform set_config('app.bono_operacion', 'on', true);

    select array_agg(r.clase_id)
      into v_clases
      from public.reservas r
      join public.clases c on c.id = r.clase_id
     where r.user_id = p_user
       and c.horario > now();

    if v_clases is null then
        return;
    end if;

    foreach v_clase in array v_clases loop
        select status
          into v_status
          from public.reservas
         where clase_id = v_clase
           and user_id = p_user
           for update;

        delete from public.reservas
         where clase_id = v_clase
           and user_id = p_user;

        -- Plaza confirmada liberada: asciende al primero de la espera con saldo.
        if v_status = 'confirmada' then
            v_promocionado := null;
            for v_promocionado in
                select e.user_id
                  from public.reservas e
                 where e.clase_id = v_clase
                   and e.status = 'espera'
                 order by e.posicion, e.created_at
                   for update
            loop
                select saldo_clases
                  into v_saldo
                  from public.profiles
                 where id = v_promocionado
                   for update;

                if v_saldo > 0 then
                    update public.reservas
                       set status = 'confirmada',
                           posicion = null
                     where clase_id = v_clase
                       and user_id = v_promocionado;

                    update public.profiles
                       set saldo_clases = saldo_clases - 1
                     where id = v_promocionado;

                    exit;
                end if;

                v_promocionado := null;
            end loop;
        end if;

        -- Mantiene la lista de espera con posiciones consecutivas.
        with ordenadas as (
            select id,
                   row_number() over (order by posicion, created_at) as nueva_pos
              from public.reservas
             where clase_id = v_clase
               and status = 'espera'
        )
        update public.reservas r
           set posicion = o.nueva_pos
          from ordenadas o
         where r.id = o.id;
    end loop;
end;
$$;

-- Solo la usan las funciones de abajo. Ningún cliente puede llamarla: si no,
-- cualquiera podría quitar las reservas de otro.
revoke all on function public.liberar_reservas_usuario(uuid) from public, anon, authenticated;

-- =====================================================================
-- RPC: eliminar_mi_cuenta
-- =====================================================================
create or replace function public.eliminar_mi_cuenta()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    if public.es_superadmin() then
        raise exception 'Una cuenta de administrador no se puede eliminar desde la app. Pide a otro administrador que la elimine.'
            using errcode = 'P0001';
    end if;

    perform public.liberar_reservas_usuario(v_uid);

    update public.clases set created_by = null where created_by = v_uid;
    update public.entrenamiento_dia set created_by = null where created_by = v_uid;

    -- Borra la cuenta de acceso; en cascada: perfil, reservas, móviles
    -- registrados, sesiones e identidades.
    delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.eliminar_mi_cuenta() from public, anon;
grant execute on function public.eliminar_mi_cuenta() to authenticated;

-- =====================================================================
-- RPC: eliminar_usuario (superadministrador) — ahora borra la cuenta entera
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

    -- Rechaza la autoeliminacion (Req 6.7).
    if target_user_id = auth.uid() then
        raise exception 'Un superadministrador no puede eliminarse a si mismo'
            using errcode = '42501';
    end if;

    if not exists (select 1 from public.profiles where id = target_user_id) then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;

    perform public.liberar_reservas_usuario(target_user_id);

    update public.clases set created_by = null where created_by = target_user_id;
    update public.entrenamiento_dia set created_by = null where created_by = target_user_id;

    -- Borra la cuenta de acceso; en cascada el perfil y todo lo asociado.
    delete from auth.users where id = target_user_id;

    -- Perfil sin cuenta de acceso (no debería existir): se borra igualmente.
    delete from public.profiles where id = target_user_id;
end;
$$;

revoke all on function public.eliminar_usuario(uuid) from public, anon;
grant execute on function public.eliminar_usuario(uuid) to authenticated;

-- =====================================================================
-- Storage: el superadministrador puede borrar fotos de perfil ajenas
-- =====================================================================
drop policy if exists avatars_delete_superadmin on storage.objects;
create policy avatars_delete_superadmin
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'avatars'
        and public.es_superadmin()
    );
