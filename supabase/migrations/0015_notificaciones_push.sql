-- Migration: 0015_notificaciones_push.sql
-- Feature: gym-management-app (Olympus)
--
-- Notificaciones push (Firebase Cloud Messaging) para avisar al Usuario cuando
-- pasa de la lista de espera a tener plaza confirmada.
--
--   * Tabla `dispositivos_push`: Firebase Installation ID (FID) de cada móvil y
--     su Usuario. FCM ha sustituido los tokens de registro por el FID como
--     destino de envío. Sin políticas RLS: ningún cliente la lee ni la escribe
--     directamente; solo las RPC de abajo (SECURITY DEFINER) y la Edge
--     Function (service role).
--   * RPC `registrar_dispositivo(p_fid, p_plataforma)`: asocia el FID al
--     Usuario de la sesión. Si el FID ya era de otro Usuario (mismo móvil,
--     otra cuenta) pasa al Usuario actual, para no avisar a quien ya no está.
--   * RPC `eliminar_dispositivo(p_fid)`: la app la llama al cerrar sesión.
--   * Trigger `reservas_notificar_plaza`: cuando una reserva pasa de 'espera' a
--     'confirmada' (promoción de `cancelar_reserva`), llama a la Edge Function
--     `notificar-plaza` mediante pg_net. La llamada es asíncrona y solo sale si
--     la transacción se confirma.
--
-- Requisitos previos (una sola vez, desde el SQL Editor, NO en el repo):
--   select vault.create_secret('https://<ref>.supabase.co', 'olympus_project_url');
--   select vault.create_secret('<secreto compartido>', 'olympus_push_secret');
-- El secreto compartido debe coincidir con el secreto OLYMPUS_PUSH_SECRET de
-- la Edge Function. Si faltan, el trigger no hace nada (no rompe la
-- cancelación).

create extension if not exists pg_net with schema extensions;

-- =====================================================================
-- Tabla de dispositivos
-- =====================================================================
create table if not exists public.dispositivos_push (
    fid        text        primary key,
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    plataforma text        not null check (plataforma in ('android', 'ios')),
    updated_at timestamptz not null default now()
);

create index if not exists dispositivos_push_user_id_idx
    on public.dispositivos_push (user_id);

alter table public.dispositivos_push enable row level security;
revoke all on table public.dispositivos_push from anon, authenticated;

-- =====================================================================
-- RPC: registrar_dispositivo
-- =====================================================================
create or replace function public.registrar_dispositivo(
    p_fid        text,
    p_plataforma text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'No autenticado: se requiere una sesion activa'
            using errcode = '42501';
    end if;

    if p_fid is null or length(p_fid) = 0 or length(p_fid) > 4096 then
        raise exception 'Identificador de dispositivo no valido'
            using errcode = '22023';
    end if;

    if p_plataforma not in ('android', 'ios') then
        raise exception 'Plataforma no valida'
            using errcode = '22023';
    end if;

    insert into public.dispositivos_push (fid, user_id, plataforma, updated_at)
    values (p_fid, auth.uid(), p_plataforma, now())
    on conflict (fid) do update
       set user_id    = excluded.user_id,
           plataforma = excluded.plataforma,
           updated_at = now();
end;
$$;

-- =====================================================================
-- RPC: eliminar_dispositivo
-- =====================================================================
create or replace function public.eliminar_dispositivo(p_fid text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        return;
    end if;

    delete from public.dispositivos_push
     where fid = p_fid
       and user_id = auth.uid();
end;
$$;

revoke all on function public.registrar_dispositivo(text, text) from public, anon;
revoke all on function public.eliminar_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text) to authenticated;
grant execute on function public.eliminar_dispositivo(text) to authenticated;

-- =====================================================================
-- Trigger: avisar al pasar de lista de espera a plaza confirmada
-- =====================================================================
create or replace function public.notificar_plaza_conseguida()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_url    text;
    v_secret text;
begin
    -- Un fallo al preparar el aviso nunca debe deshacer la cancelación ni la
    -- promoción: se registra como WARNING y se continúa.
    begin
        select decrypted_secret into v_url
          from vault.decrypted_secrets
         where name = 'olympus_project_url';

        select decrypted_secret into v_secret
          from vault.decrypted_secrets
         where name = 'olympus_push_secret';

        if v_url is null or v_secret is null then
            raise warning 'notificar_plaza_conseguida: faltan los secretos de Vault';
            return new;
        end if;

        perform net.http_post(
            url     := rtrim(v_url, '/') || '/functions/v1/notificar-plaza',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-olympus-secret', v_secret
            ),
            body    := jsonb_build_object(
                'user_id', new.user_id,
                'clase_id', new.clase_id
            )
        );
    exception when others then
        raise warning 'notificar_plaza_conseguida: %', sqlerrm;
    end;

    return new;
end;
$$;

revoke all on function public.notificar_plaza_conseguida() from public, anon, authenticated;

drop trigger if exists reservas_notificar_plaza on public.reservas;
create trigger reservas_notificar_plaza
    after update of status on public.reservas
    for each row
    when (old.status = 'espera' and new.status = 'confirmada')
    execute function public.notificar_plaza_conseguida();
