-- =====================================================================
-- apply_all_migrations.sql
-- Feature: gym-management-app (Olympus)
-- Script combinado para aplicar TODAS las migraciones base en orden desde el
-- SQL Editor del dashboard de Supabase. Pega este contenido completo y pulsa
-- "Run". Es idempotente (se puede re-ejecutar sin romper nada).
--
-- Orden: 0001_schema.sql -> 0002_trigger_helper.sql -> 0003_rls.sql ->
--        0004_rpc_bono.sql -> 0005_rpc_admin.sql -> 0006_rpc_reservas.sql ->
--        0007_entrenamiento_dia.sql -> 0008_aforo_view.sql
-- =====================================================================


-- #####################################################################
-- # 0001_schema.sql  -> Tablas base y constraints
-- #####################################################################

-- Necesario para gen_random_uuid()
create extension if not exists pgcrypto;

-- profiles (extiende auth.users). Modelo ampliable: columnas conocidas + metadata JSONB.
create table if not exists public.profiles (
    id           uuid        primary key references auth.users (id) on delete cascade,
    nombre       text        not null,
    apellidos    text        not null,
    foto_url     text        null,
    email        text        not null unique,
    saldo_clases int         not null default 10 check (saldo_clases between 0 and 10),
    estado       text        not null default 'activo' check (estado in ('activo', 'suspendido')),
    rol          text        not null default 'usuario' check (rol in ('usuario', 'superadmin')),
    metadata     jsonb       not null default '{}'::jsonb,
    created_at   timestamptz not null default now()
);

-- clases (sesiones del calendario)
create table if not exists public.clases (
    id         uuid        primary key default gen_random_uuid(),
    horario    timestamptz not null,
    aforo      int         not null check (aforo between 1 and 10),
    monitor    text        not null,
    created_by uuid        references public.profiles (id),
    created_at timestamptz not null default now()
);

-- reservas (reserva confirmada + lista de espera unificadas; 1 fila por usuario-clase)
create table if not exists public.reservas (
    id         uuid        primary key default gen_random_uuid(),
    clase_id   uuid        not null references public.clases (id) on delete cascade,
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    status     text        not null check (status in ('confirmada', 'espera')),
    posicion   int         null,
    created_at timestamptz not null default now(),
    unique (clase_id, user_id)
);


-- #####################################################################
-- # 0002_trigger_helper.sql  -> Trigger de alta de perfil + helper de rol
-- #####################################################################

-- handle_new_user(): tras crear una cuenta en auth.users, inserta su fila espejo
-- en public.profiles con saldo 10 y estado 'activo', tomando nombre/apellidos de
-- la metadata del registro.
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
        10,
        'activo'
    );
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- es_superadmin(): true si el llamante (auth.uid()) tiene rol 'superadmin'.
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


-- #####################################################################
-- # 0003_rls.sql  -> Row Level Security + politicas
-- #####################################################################

alter table public.profiles enable row level security;
alter table public.clases   enable row level security;
alter table public.reservas enable row level security;

-- profiles SELECT: propio o superadmin
drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin
    on public.profiles
    for select
    to authenticated
    using (auth.uid() = id or public.es_superadmin());

-- profiles UPDATE: solo la propia fila (columnas sensibles protegidas por trigger)
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
    on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Trigger de inmutabilidad: usuario estandar no puede cambiar saldo_clases/estado/rol
create or replace function public.profiles_proteger_columnas()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if current_setting('role', true) is distinct from 'authenticated'
       and current_user <> 'authenticated' then
        return new;
    end if;

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

-- clases SELECT: cualquier autenticado; escritura solo superadmin
drop policy if exists clases_select_autenticados on public.clases;
create policy clases_select_autenticados
    on public.clases
    for select
    to authenticated
    using (true);

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

-- reservas SELECT/INSERT/DELETE: solo filas propias
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


-- #####################################################################
-- # 0004_rpc_bono.sql  -> RPC de gestion del bono (superadmin)
-- #####################################################################

-- restablecer_bono(target_user_id): valida superadmin y fija el saldo en 10.
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

    update public.profiles
       set saldo_clases = 10
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- ajustar_bono(target_user_id, valor): valida superadmin y 0 <= valor <= 10.
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

    update public.profiles
       set saldo_clases = valor
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

grant execute on function public.restablecer_bono(uuid) to authenticated;
grant execute on function public.ajustar_bono(uuid, int) to authenticated;


-- #####################################################################
-- # 0005_rpc_admin.sql  -> RPC de gestion de usuarios (superadmin)
-- #####################################################################

-- suspender_usuario(target_user_id): valida superadmin y da de baja (estado='suspendido').
create or replace function public.suspender_usuario(target_user_id uuid)
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

    update public.profiles
       set estado = 'suspendido'
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- reactivar_usuario(target_user_id): valida superadmin y reactiva (estado='activo').
create or replace function public.reactivar_usuario(target_user_id uuid)
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

    update public.profiles
       set estado = 'activo'
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- eliminar_usuario(target_user_id): valida superadmin, rechaza autoeliminacion y
-- elimina el registro (las reservas se borran en cascada).
create or replace function public.eliminar_usuario(target_user_id uuid)
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

    if target_user_id = auth.uid() then
        raise exception 'Un superadministrador no puede eliminarse a si mismo'
            using errcode = '42501';
    end if;

    delete from public.profiles
     where id = target_user_id;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- conceder_superadmin(target_user_id): valida superadmin y asigna el rol
-- respetando el maximo de 2 (bloqueo FOR UPDATE + conteo < 2).
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
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    select rol
      into rol_objetivo
      from public.profiles
     where id = target_user_id
       for update;

    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;

    if rol_objetivo = 'superadmin' then
        return;
    end if;

    perform 1
       from public.profiles
      where rol = 'superadmin'
        for update;

    select count(*)
      into total_superadmins
      from public.profiles
     where rol = 'superadmin';

    if total_superadmins >= 2 then
        raise exception 'Se ha alcanzado el numero maximo de superadministradores'
            using errcode = 'P0001';
    end if;

    update public.profiles
       set rol = 'superadmin'
     where id = target_user_id;
end;
$$;

grant execute on function public.suspender_usuario(uuid) to authenticated;
grant execute on function public.reactivar_usuario(uuid) to authenticated;
grant execute on function public.eliminar_usuario(uuid) to authenticated;
grant execute on function public.conceder_superadmin(uuid) to authenticated;


-- #####################################################################
-- # 0006_rpc_reservas.sql  -> RPC transaccionales de reservas y cancelacion
-- #####################################################################

-- reservar_clase(p_clase_id): en una transaccion valida saldo > 0, aforo,
-- duplicados y limite de espera (< 20); crea reserva confirmada y descuenta 1
-- del bono, o encola en espera (FIFO) sin tocar el bono. Bloqueos FOR UPDATE
-- sobre el profile y las reservas de la clase evitan la carrera por la ultima
-- plaza (Req 8.3, 8.4, 8.5, 8.6, 8.12). Devuelve jsonb con el desenlace.
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

    -- Req 8.4: sin clases en el bono -> rechazo.
    if v_saldo <= 0 then
        raise exception 'No quedan clases disponibles en tu bono'
            using errcode = 'P0001';
    end if;

    -- Req 8.6: sin duplicados (confirmada o espera).
    if exists (
        select 1
          from public.reservas
         where clase_id = p_clase_id
           and user_id = v_user_id
    ) then
        raise exception 'Ya existe una reserva para esta clase'
            using errcode = 'P0001';
    end if;

    -- Bloqueo atomico de las reservas de la clase antes de contar.
    perform 1
       from public.reservas
      where clase_id = p_clase_id
        for update;

    select count(*) filter (where status = 'confirmada'),
           count(*) filter (where status = 'espera')
      into v_confirmadas, v_esperas
      from public.reservas
     where clase_id = p_clase_id;

    -- Req 8.3: aforo libre -> confirmada + descuento de 1.
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

    -- Req 8.12: lista de espera llena.
    if v_esperas >= 20 then
        raise exception 'La lista de espera está completa'
            using errcode = 'P0001';
    end if;

    -- Req 8.5: encolar al final (FIFO), sin tocar el saldo.
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

-- cancelar_reserva(p_clase_id): libera plaza; reembolsa 1 solo si antelacion
-- >= 2h; promociona de forma atomica al primer usuario de la espera con saldo
-- > 0 (FIFO); si era entrada de espera, la elimina sin tocar el bono
-- (Req 8.7, 8.8, 8.9, 8.11). Devuelve jsonb con el detalle.
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

    -- Req 8.11: cancelacion de entrada en espera -> eliminar y renumerar FIFO.
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

    -- Reserva confirmada: obtener horario y liberar la plaza.
    select horario
      into v_horario
      from public.clases
     where id = p_clase_id;

    delete from public.reservas
     where clase_id = p_clase_id
       and user_id = v_user_id;

    -- Req 8.7/8.8: reembolso solo si antelacion >= 2h (clamp a 10).
    if v_horario is not null
       and (v_horario - now()) >= interval '2 hours' then
        update public.profiles
           set saldo_clases = least(saldo_clases + 1, 10)
         where id = v_user_id;
        v_hubo_reembolso := true;
    end if;

    -- Req 8.9: promocion atomica del primer usuario de la espera con saldo > 0.
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

    -- Renumera las esperas restantes si hubo promocion.
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

grant execute on function public.reservar_clase(uuid) to authenticated;
grant execute on function public.cancelar_reserva(uuid) to authenticated;


-- #####################################################################
-- # 0007_entrenamiento_dia.sql  -> Plan de entrenamiento del dia (por fecha)
-- #####################################################################

-- entrenamiento_dia: una fila por fecha con la lista ordenada de actividades
-- del dia. Lectura para autenticados; escritura solo superadmin.
create table if not exists public.entrenamiento_dia (
    id          uuid        primary key default gen_random_uuid(),
    fecha       date        not null unique,
    actividades text[]      not null default '{}',
    created_by  uuid        references public.profiles (id),
    created_at  timestamptz not null default now()
);

alter table public.entrenamiento_dia enable row level security;

drop policy if exists entrenamiento_dia_select_autenticados on public.entrenamiento_dia;
create policy entrenamiento_dia_select_autenticados
    on public.entrenamiento_dia
    for select
    to authenticated
    using (true);

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


-- #####################################################################
-- # 0008_aforo_view.sql  -> Ocupacion de una Clase (solo lectura, sin identidades)
-- #####################################################################

-- ocupacion_clase(p_clase_id): devuelve jsonb { confirmadas, espera } con el
-- recuento de reservas de la Clase para cualquier Usuario autenticado, sin
-- exponer identidades. SECURITY DEFINER + search_path fijo para que la RLS de
-- `reservas` no oculte filas ajenas al Usuario normal al contar (Req 8.1, 7.3).
create or replace function public.ocupacion_clase(p_clase_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_confirmadas int;
    v_esperas     int;
begin
    if auth.uid() is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    select count(*) filter (where status = 'confirmada'),
           count(*) filter (where status = 'espera')
      into v_confirmadas, v_esperas
      from public.reservas
     where clase_id = p_clase_id;

    return jsonb_build_object(
        'confirmadas', coalesce(v_confirmadas, 0),
        'espera', coalesce(v_esperas, 0)
    );
end;
$$;

grant execute on function public.ocupacion_clase(uuid) to authenticated;


-- #####################################################################
-- # Verificacion rapida (opcional): descomenta para comprobar el resultado
-- #####################################################################
-- select table_name from information_schema.tables
--   where table_schema = 'public' and table_name in ('profiles','clases','reservas');
-- select tablename, policyname from pg_policies where schemaname = 'public' order by tablename;
