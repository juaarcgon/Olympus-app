-- Migration: 0006_rpc_reservas.sql
-- Feature: gym-management-app (Olympus)
-- Funciones RPC transaccionales para la reserva y cancelacion de Clases
-- (Servicio_Reservas). Replican la semantica del modelo de dominio puro
-- lib/features/reservas/domain/reservas_model.dart, pero operando de forma
-- atomica sobre la base de datos para resistir la concurrencia (p. ej. la
-- carrera por la ultima plaza libre).
--   * reservar_clase(p_clase_id): valida saldo > 0, aforo, duplicados y limite
--     de lista de espera (< 20); en una sola transaccion crea la reserva
--     confirmada y decrementa el bono, o encola en espera (FIFO) sin tocar el
--     bono (Req 8.3, 8.4, 8.5, 8.6, 8.12).
--   * cancelar_reserva(p_clase_id): libera la plaza; reembolsa 1 clase solo si
--     la antelacion es >= 2h; promociona de forma atomica al primer usuario de
--     la espera con saldo > 0 (FIFO); si la entrada era de espera, la elimina
--     sin tocar el bono (Req 8.7, 8.8, 8.9, 8.11).
-- Ambas son SECURITY DEFINER con search_path fijo y actuan sobre auth.uid()
-- (el Usuario de la sesion). Al ser SECURITY DEFINER corren con los privilegios
-- del propietario y pueden modificar saldo_clases pese al trigger de
-- inmutabilidad de columnas (profiles_inmutabilidad_columnas) y pese a la
-- ausencia de politica UPDATE sobre reservas (la promocion solo ocurre aqui).
-- Control de concurrencia: se bloquean con FOR UPDATE la fila de profile del
-- usuario y las filas de reservas de la clase antes de contar/insertar, de modo
-- que dos reservas simultaneas se serializan y el aforo nunca se supera.
-- Se usa RAISE EXCEPTION USING ERRCODE/MESSAGE para senalar las condiciones de
-- negocio (saldo cero, duplicado, lista llena, sin reserva), acorde a la
-- estrategia de Error Handling del diseno. El rango 0..10 del bono lo garantiza
-- ademas el CHECK de profiles.saldo_clases.
-- _Requirements: 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.11, 8.12_
-- _Design: Funciones RPC del backend_

-- =====================================================================
-- Funcion: reservar_clase(p_clase_id)
-- Reserva una plaza para el Usuario de la sesion en la Clase indicada, en una
-- unica transaccion (Req 8.3, 8.4, 8.5, 8.6, 8.12).
-- Devuelve un jsonb con el desenlace: { status, posicion, saldo_resultante }.
--   * status = 'confirmada': plaza confirmada; posicion = null; se descuenta 1.
--   * status = 'espera': encolado en lista de espera; posicion = puesto FIFO;
--     el saldo no cambia.
-- =====================================================================
create or replace function public.reservar_clase(p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id      uuid;
    v_aforo        int;
    v_saldo        int;
    v_confirmadas  int;
    v_esperas      int;
    v_posicion     int;
begin
    -- Usuario de la sesion: sin JWT no hay reserva posible (Req 7.3).
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    -- Carga la Clase y su aforo. Si no existe, se informa como no encontrada.
    select aforo
      into v_aforo
      from public.clases
     where id = p_clase_id;

    if not found then
        raise exception 'Clase no encontrada'
            using errcode = 'P0002';
    end if;

    -- Bloquea la fila de profile del usuario para serializar lecturas/escrituras
    -- de su saldo dentro de esta transaccion.
    select saldo_clases
      into v_saldo
      from public.profiles
     where id = v_user_id
       for update;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;

    -- Req 8.4: sin clases en el bono -> rechazo sin crear nada.
    if v_saldo <= 0 then
        raise exception 'No quedan clases disponibles en tu bono'
            using errcode = 'P0001';
    end if;

    -- Req 8.6: no se permiten reservas ni entradas de espera duplicadas.
    if exists (
        select 1
          from public.reservas
         where clase_id = p_clase_id
           and user_id = v_user_id
    ) then
        raise exception 'Ya existe una reserva para esta clase'
            using errcode = 'P0001';
    end if;

    -- Bloquea FOR UPDATE las reservas de esta Clase para contar de forma
    -- atomica y evitar la carrera por la ultima plaza libre.
    perform 1
       from public.reservas
      where clase_id = p_clase_id
        for update;

    select count(*) filter (where status = 'confirmada'),
           count(*) filter (where status = 'espera')
      into v_confirmadas, v_esperas
      from public.reservas
     where clase_id = p_clase_id;

    -- Req 8.3: hay aforo libre -> reserva confirmada y descuento de 1 clase.
    if v_confirmadas < v_aforo then
        insert into public.reservas (clase_id, user_id, status, posicion)
        values (p_clase_id, v_user_id, 'confirmada', null);

        update public.profiles
           set saldo_clases = saldo_clases - 1
         where id = v_user_id
        returning saldo_clases into v_saldo;

        return jsonb_build_object(
            'status', 'confirmada',
            'posicion', null,
            'saldo_resultante', v_saldo
        );
    end if;

    -- Aforo completo. Req 8.12: lista de espera llena (>= 20) -> rechazo.
    if v_esperas >= 20 then
        raise exception 'La lista de espera está completa'
            using errcode = 'P0001';
    end if;

    -- Req 8.5: aforo completo con hueco en espera -> al final (FIFO), sin
    -- modificar el saldo. La posicion es 1-indexada (puesto en la cola).
    v_posicion := v_esperas + 1;

    insert into public.reservas (clase_id, user_id, status, posicion)
    values (p_clase_id, v_user_id, 'espera', v_posicion);

    return jsonb_build_object(
        'status', 'espera',
        'posicion', v_posicion,
        'saldo_resultante', v_saldo
    );
end;
$$;

-- =====================================================================
-- Funcion: cancelar_reserva(p_clase_id)
-- Cancela la participacion del Usuario de la sesion en la Clase, en una unica
-- transaccion (Req 8.7, 8.8, 8.9, 8.11).
-- Devuelve un jsonb con el detalle:
--   { libero_plaza, hubo_reembolso, promocionado, saldo_resultante }.
-- =====================================================================
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
    -- Usuario de la sesion: sin JWT no hay cancelacion posible (Req 7.3).
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    -- Carga y bloquea la reserva del usuario para esta Clase.
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

    -- Req 8.11: cancelacion de una entrada en lista de espera. Se elimina su
    -- entrada y se renumeran las posteriores para mantener la cola FIFO. El
    -- saldo no se toca y no hay promocion (no se libera plaza confirmada).
    if v_status = 'espera' then
        delete from public.reservas
         where clase_id = p_clase_id
           and user_id = v_user_id;

        -- Renumera las esperas restantes segun su orden FIFO (posicion luego
        -- fecha de creacion) para que las posiciones sean consecutivas.
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

    -- Reserva confirmada (Req 8.7/8.8/8.9).
    -- Obtiene el horario de la Clase para calcular la antelacion.
    select horario
      into v_horario
      from public.clases
     where id = p_clase_id;

    -- Libera la plaza confirmada.
    delete from public.reservas
     where clase_id = p_clase_id
       and user_id = v_user_id;

    -- Req 8.7: reembolso de 1 clase solo si la antelacion es >= 2h.
    -- Req 8.8: con menos de 2h no hay reembolso. El rango 0..10 lo protege el
    -- CHECK de profiles.saldo_clases; least(...) evita superar el maximo.
    if v_horario is not null
       and (v_horario - now()) >= interval '2 hours' then
        update public.profiles
           set saldo_clases = least(saldo_clases + 1, 10)
         where id = v_user_id;
        v_hubo_reembolso := true;
    end if;

    -- Req 8.9: promocion atomica del primer usuario de la espera con saldo > 0.
    -- Se bloquean las esperas de la Clase ordenadas por posicion y fecha, y se
    -- recorren hasta encontrar un candidato elegible (saldo_clases > 0).
    for v_promocionado in
        select r.user_id
          from public.reservas r
          join public.profiles p on p.id = r.user_id
         where r.clase_id = p_clase_id
           and r.status = 'espera'
         order by r.posicion, r.created_at
           for update of r
    loop
        -- Bloquea el profile del candidato y comprueba su saldo dentro de la
        -- transaccion (defensa frente a cambios concurrentes del bono).
        select saldo_clases
          into v_saldo
          from public.profiles
         where id = v_promocionado
           for update;

        if v_saldo > 0 then
            -- Promociona: pasa a confirmada, libera la posicion de espera y
            -- descuenta 1 clase del candidato (Req 8.9).
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

        -- Candidato sin saldo: no es elegible, se descarta y se sigue buscando.
        v_promocionado := null;
    end loop;

    -- Si hubo promocion, renumera las esperas restantes para mantener la cola
    -- FIFO consecutiva tras retirar al promocionado.
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

-- =====================================================================
-- Permisos de ejecucion
-- Se concede EXECUTE al rol authenticated; la autorizacion por sesion
-- (auth.uid()) y las reglas de negocio se comprueban dentro del cuerpo de cada
-- funcion. El rol anon no recibe permiso: sin sesion no hay acceso (Req 7.3).
-- =====================================================================
grant execute on function public.reservar_clase(uuid) to authenticated;
grant execute on function public.cancelar_reserva(uuid) to authenticated;
