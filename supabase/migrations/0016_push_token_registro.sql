-- Migration: 0016_push_token_registro.sql
-- Feature: gym-management-app (Olympus)
--
-- Cambia el identificador de los móviles de Firebase Installation ID (FID) a
-- token de registro de FCM.
--
-- Motivo: con la API nueva de firebase_messaging 17 (`register()` +
-- `onRegistered`) la app nunca llegó a entregar el FID, así que ningún móvil
-- se registraba. `getToken()` devuelve el token de forma directa y probada.
-- Google lo ha marcado como obsoleto, pero sigue funcionando y la API HTTP v1
-- de FCM lo acepta en el campo `token`.
--
-- La tabla estaba vacía cuando se escribió esta migración, así que el cambio
-- no pierde datos.

alter table public.dispositivos_push rename column fid to token;

drop function if exists public.registrar_dispositivo(text, text);
drop function if exists public.eliminar_dispositivo(text);

-- =====================================================================
-- RPC: registrar_dispositivo
-- =====================================================================
create function public.registrar_dispositivo(
    p_token      text,
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

    if p_token is null or length(p_token) = 0 or length(p_token) > 4096 then
        raise exception 'Identificador de dispositivo no valido'
            using errcode = '22023';
    end if;

    if p_plataforma not in ('android', 'ios') then
        raise exception 'Plataforma no valida'
            using errcode = '22023';
    end if;

    insert into public.dispositivos_push (token, user_id, plataforma, updated_at)
    values (p_token, auth.uid(), p_plataforma, now())
    on conflict (token) do update
       set user_id    = excluded.user_id,
           plataforma = excluded.plataforma,
           updated_at = now();
end;
$$;

-- =====================================================================
-- RPC: eliminar_dispositivo
-- =====================================================================
create function public.eliminar_dispositivo(p_token text)
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
     where token = p_token
       and user_id = auth.uid();
end;
$$;

revoke all on function public.registrar_dispositivo(text, text) from public, anon;
revoke all on function public.eliminar_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text) to authenticated;
grant execute on function public.eliminar_dispositivo(text) to authenticated;
