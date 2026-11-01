-- Migration: 0013_cancelar_clase_no_empezada.sql
-- Feature: gym-management-app (Olympus)
--
-- Impide cancelar una reserva (confirmada o en lista de espera) de una Clase
-- cuya hora de inicio ya ha llegado o pasado. Hasta ahora se podía cancelar,
-- por ejemplo, a las 19:00 una clase de las 17:00 ya terminada. La regla es la
-- misma que para reservar (migración 0012): solo se actúa sobre Clases cuyo
-- Horario_Clase es ESTRICTAMENTE futuro respecto a now().
--
-- Se redefine `cancelar_reserva` con `create or replace` partiendo de la
-- versión vigente de la migración 0010 y añadiendo la comprobación temporal
-- antes de tocar nada. El resto de la lógica (reembolso con >= 2 h, promoción
-- FIFO desde la lista de espera, renumeración) no cambia.
--
-- IMPORTANTE: no eliminar el `set_config('app.bono_operacion', ...)`. Sin esa
-- marca el trigger `profiles_proteger_columnas` rechaza el reembolso y la
-- promoción con ERRCODE 42501 ("No tienes autorización").
-- _Requirements: 8.7, 8.8, 8.9, 8.11_

create or replace function public.cancelar_reserva(p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id        uuid;
    v_status         text;
    v_horario        timestamptz;
    v_saldo          int;
    v_hubo_reembolso boolean := false;
    v_promocionado   uuid;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    -- Marca la operación del sistema para que el trigger permita tocar el bono
    -- (migración 0010).
    perform set_config('app.bono_operacion', 'on', true);

    -- Nueva regla: no se puede cancelar una Clase que ya ha empezado o pasado.
    select horario
      into v_horario
      from public.clases
     where id = p_clase_id;

    if v_horario is not null and v_horario <= now() then
        raise exception 'No se puede cancelar una clase que ya ha empezado'
            using errcode = 'P0001';
    end if;

    select status
      into v_status
      from public.reservas
     where clase_id = p_clase_id
       and user_id = v_user_id
       for update;

    if not found then
        raise exception 'No tienes reserva en esta clase'
            using errcode = 'P0002';
    end if;

    if v_status = 'espera' then
        delete from public.reservas
         where clase_id = p_clase_id
           and user_id = v_user_id;

        with ordenadas as (
            select id,
                   row_number() over (order by posicion, created_at) as nueva_pos
              from public.reservas
             where clase_id = p_clase_id
               and status = 'espera'
        )
        update public.reservas r
           set posicion = o.nueva_pos
          from ordenadas o
         where r.id = o.id;

        return jsonb_build_object(
            'libero_plaza', false,
            'hubo_reembolso', false,
            'promocionado', null,
            'saldo_resultante', null
        );
    end if;

    delete from public.reservas
     where clase_id = p_clase_id
       and user_id = v_user_id;

    if v_horario is not null
       and (v_horario - now()) >= interval '2 hours' then
        update public.profiles
           set saldo_clases = least(saldo_clases + 1, 10)
         where id = v_user_id;
        v_hubo_reembolso := true;
    end if;

    for v_promocionado in
        select r.user_id
          from public.reservas r
          join public.profiles p on p.id = r.user_id
         where r.clase_id = p_clase_id
           and r.status = 'espera'
         order by r.posicion, r.created_at
           for update of r
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
             where clase_id = p_clase_id
               and user_id = v_promocionado;

            update public.profiles
               set saldo_clases = saldo_clases - 1
             where id = v_promocionado;

            exit;
        end if;

        v_promocionado := null;
    end loop;

    if v_promocionado is not null then
        with ordenadas as (
            select id,
                   row_number() over (order by posicion, created_at) as nueva_pos
              from public.reservas
             where clase_id = p_clase_id
               and status = 'espera'
        )
        update public.reservas r
           set posicion = o.nueva_pos
          from ordenadas o
         where r.id = o.id;
    end if;

    return jsonb_build_object(
        'libero_plaza', true,
        'hubo_reembolso', v_hubo_reembolso,
        'promocionado', v_promocionado,
        'saldo_resultante', null
    );
end;
$$;

grant execute on function public.cancelar_reserva(uuid) to authenticated;
