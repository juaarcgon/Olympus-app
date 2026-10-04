-- Migration: 0008_aforo_view.sql
-- Feature: gym-management-app (Olympus)
-- Funcion de solo lectura para exponer la ocupacion de una Clase a cualquier
-- Usuario autenticado SIN revelar la identidad de los apuntados.
--   * ocupacion_clase(p_clase_id): devuelve un jsonb { confirmadas, espera }
--     con el numero de reservas confirmadas y en lista de espera de la Clase.
-- La RLS de `reservas` (migracion 0003) limita la lectura directa a las filas
-- propias de cada Usuario, por lo que un Usuario normal no puede contar la
-- ocupacion real consultando la tabla. Esta funcion es SECURITY DEFINER con
-- search_path fijo: corre con los privilegios del propietario y permite el
-- recuento agregado sin exponer identidades (solo cardinalidades), de modo que
-- la pantalla del calendario pueda mostrar el aforo "confirmadas/aforo" a
-- cualquier Usuario. La lista nominal de apuntados sigue siendo visible solo
-- para el superadministrador mediante la lectura directa de `reservas` (RLS).
-- Esta migracion es aditiva: NO modifica tablas, triggers ni politicas previas
-- (0001-0007). Solo crea una funcion nueva y concede su EXECUTE.
-- _Requirements: 8.1, 7.3_
-- _Design: Capas del cliente Flutter; Servicio_Reservas; Funciones RPC del backend_

-- =====================================================================
-- Funcion: ocupacion_clase(p_clase_id)
-- Cuenta las reservas confirmadas y en espera de la Clase indicada y las
-- devuelve como jsonb { confirmadas, espera }. No expone ningun identificador
-- de Usuario, solo cardinalidades agregadas (Req 8.1).
-- SECURITY DEFINER + search_path fijo: el recuento corre con los privilegios
-- del propietario para que la RLS de `reservas` no oculte filas ajenas al
-- Usuario normal, sin revelar a quien pertenecen.
-- =====================================================================
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
    -- Usuario de la sesion: sin JWT no hay acceso a datos (Req 7.3).
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

-- =====================================================================
-- Permisos de ejecucion
-- Se concede EXECUTE al rol authenticated; la funcion solo devuelve conteos
-- agregados, nunca identidades. El rol anon no recibe permiso: sin sesion no
-- hay acceso (Req 7.3).
-- =====================================================================
grant execute on function public.ocupacion_clase(uuid) to authenticated;
