-- Migration: 0014_apuntados_clase.sql
-- Feature: gym-management-app (Olympus)
--
-- Permite que TODOS los Usuarios autenticados vean quién está apuntado a una
-- Clase (confirmados y lista de espera con su posición). Hasta ahora solo el
-- superadministrador podía ver la lista nominal, porque la RLS de `reservas` y
-- de `profiles` impide a un Usuario normal leer filas ajenas.
--
-- En lugar de abrir esas políticas (lo que expondría email, saldo, rol, etc.
-- de todos los perfiles), se añade una función de solo lectura
-- `SECURITY DEFINER` que devuelve EXCLUSIVAMENTE lo necesario para la lista:
-- user_id, nombre, apellidos, status y posicion. El user_id permite a la app
-- marcar al propio Usuario como "(tú)". Ningún otro dato del perfil sale de
-- aquí.
--
-- Mismo patrón que `ocupacion_clase` (migración 0008).

create or replace function public.apuntados_clase(p_clase_id uuid)
returns table (
    user_id   uuid,
    nombre    text,
    apellidos text,
    status    text,
    posicion  int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select r.user_id,
           p.nombre,
           p.apellidos,
           r.status,
           r.posicion
      from public.reservas r
      join public.profiles p on p.id = r.user_id
     where r.clase_id = p_clase_id
       -- Sin sesión no se devuelve nada (Req 7.3).
       and auth.uid() is not null
     order by r.status, r.posicion nulls first, r.created_at;
$$;

revoke all on function public.apuntados_clase(uuid) from public, anon;
grant execute on function public.apuntados_clase(uuid) to authenticated;
