-- Migration: 0010_fix_trigger_operacion_sistema.sql
-- Feature: gym-management-app (Olympus)
--
-- Corrige el bloqueo indebido del trigger de inmutabilidad de columnas sobre
-- `profiles` (migración 0003). El trigger `profiles_proteger_columnas`
-- intentaba distinguir el contexto privilegiado comprobando `current_user` /
-- `current_setting('role')`, pero en Supabase una función `SECURITY DEFINER`
-- puede seguir reportando el rol `authenticated` dentro del trigger. Resultado:
-- las RPC legítimas que descuentan/reembolsan el bono (reservar_clase,
-- cancelar_reserva, ajustar_bono, restablecer_bono) quedaban bloqueadas con
-- "No autorizado: el saldo de clases solo se modifica mediante operaciones del
-- sistema" (ERRCODE 42501).
--
-- Solución (patrón estándar y fiable): las operaciones del sistema marcan una
-- variable de sesión `app.bono_operacion = 'on'` dentro de su transacción, y el
-- trigger permite el cambio de columnas sensibles cuando esa marca está activa
-- (o cuando el llamante es superadmin). Un usuario estándar con un UPDATE
-- directo NO tiene la marca activa, por lo que sigue bloqueado (Req 3.3, 3.4).
--
-- Esta migración es aditiva: redefine el trigger y las cuatro RPC, sin tocar
-- tablas ni políticas. Mantiene la semántica de negocio de 0004/0006.
-- _Requirements: 3.3, 3.4, 4.2, 6.5, 6.6, 8.3, 8.7, 8.9_
-- _Design: Security and RLS Strategy; Funciones RPC del backend_

-- =====================================================================
-- Trigger de inmutabilidad: permite el cambio si hay una operación del sistema
-- marcada en la sesión (app.bono_operacion = 'on') o si el llamante es
-- superadmin. En cualquier otro caso, bloquea el cambio de saldo/estado/rol.
-- =====================================================================
create or replace function public.profiles_proteger_columnas()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Operación del sistema marcada por una RPC de confianza: se permite.
    if current_setting('app.bono_operacion', true) = 'on' then
        return new;
    end if;

    -- Un superadmin puede cambiar estas columnas (gestión de usuarios).
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

-- =====================================================================
-- restablecer_bono: marca la operación del sistema antes de fijar el saldo.
-- =====================================================================
create or replace function public.restablecer_bono(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    perform set_config('app.bono_operacion', 'on', true);

    update public.profiles
       set saldo_clases = 10
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- ajustar_bono: marca la operación del sistema antes de fijar el saldo.
-- =====================================================================
create or replace function public.ajustar_bono(target_user_id uuid, valor int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    if valor < 0 or valor > 10 then
        raise exception 'El valor del bono debe estar entre 0 y 10'
            using errcode = '22003';
    end if;

    perform set_config('app.bono_operacion', 'on', true);

    update public.profiles
       set saldo_clases = valor
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- reservar_clase: marca la operación del sistema; el resto de la lógica de
-- negocio (aforo, duplicados, lista de espera, descuento) es la de 0006.
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
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    -- Marca la operación del sistema para que el trigger permita tocar el bono.
    perform set_config('app.bono_operacion', 'on', true);

    select aforo
      into v_aforo
      from public.clases
     where id = p_clase_id;

    if not found then
        raise exception 'Clase no encontrada'
            using errcode = 'P0002';
    end if;

    select saldo_clases
      into v_saldo
      from public.profiles
     where id = v_user_id
       for update;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;

    if v_saldo <= 0 then
        raise exception 'No quedan clases disponibles en tu bono'
            using errcode = 'P0001';
    end if;

    if exists (
        select 1
          from public.reservas
         where clase_id = p_clase_id
           and user_id = v_user_id
    ) then
        raise exception 'Ya existe una reserva para esta clase'
            using errcode = 'P0001';
    end if;

    perform 1
       from public.reservas
      where clase_id = p_clase_id
        for update;

    select count(*) filter (where status = 'confirmada'),
           count(*) filter (where status = 'espera')
      into v_confirmadas, v_esperas
      from public.reservas
     where clase_id = p_clase_id;

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

    if v_esperas >= 20 then
        raise exception 'La lista de espera está completa'
            using errcode = 'P0001';
    end if;

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
-- cancelar_reserva: marca la operación del sistema; el resto de la lógica
-- (reembolso >= 2h, promoción FIFO) es la de 0006.
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
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    -- Marca la operación del sistema para que el trigger permita tocar el bono.
    perform set_config('app.bono_operacion', 'on', true);

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

    select horario
      into v_horario
      from public.clases
     where id = p_clase_id;

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
