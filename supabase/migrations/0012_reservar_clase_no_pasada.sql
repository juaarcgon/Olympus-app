-- Migration: 0012_reservar_clase_no_pasada.sql
-- Feature: gym-management-app (Olympus)
--
-- Impide reservar una Clase cuya hora de inicio ya ha llegado o pasado. Hasta
-- ahora se podía reservar (o entrar en lista de espera de) una franja que ya
-- había comenzado o incluso una del pasado. La regla nueva: solo se puede
-- reservar si el Horario_Clase es ESTRICTAMENTE futuro respecto a now().
-- Ejemplo: a las 18:00 no se puede reservar la franja de las 18:00 ni ninguna
-- anterior.
--
-- Se redefine `reservar_clase` con `create or replace` partiendo de la versión
-- vigente de la migración 0010 (que marca `app.bono_operacion` para que el
-- trigger de inmutabilidad permita descontar el bono) y añadiendo, justo tras
-- cargar la Clase, la comprobación temporal. Es la línea de defensa real del
-- backend; el cliente además oculta el botón de reservar.
--
-- IMPORTANTE: no eliminar el `set_config('app.bono_operacion', ...)`. Sin esa
-- marca el trigger `profiles_proteger_columnas` rechaza el descuento del saldo
-- con ERRCODE 42501 y la app muestra "No tienes autorización".
-- _Requirements: 8.3, 8.4, 8.5, 8.6, 8.12_

create or replace function public.reservar_clase(p_clase_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id      uuid;
    v_aforo        int;
    v_horario      timestamptz;
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

    -- Marca la operación del sistema para que el trigger permita tocar el bono
    -- (migración 0010).
    perform set_config('app.bono_operacion', 'on', true);

    -- Carga la Clase: aforo y horario. Si no existe, se informa como no
    -- encontrada.
    select aforo, horario
      into v_aforo, v_horario
      from public.clases
     where id = p_clase_id;

    if not found then
        raise exception 'Clase no encontrada'
            using errcode = 'P0002';
    end if;

    -- Nueva regla: no se puede reservar una Clase cuya hora ya ha llegado o
    -- pasado. La hora de inicio debe ser estrictamente futura.
    if v_horario <= now() then
        raise exception 'No se puede reservar una clase que ya ha empezado'
            using errcode = 'P0001';
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

grant execute on function public.reservar_clase(uuid) to authenticated;
