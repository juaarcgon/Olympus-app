-- Migration: 0004_rpc_bono.sql
-- Feature: gym-management-app (Olympus)
-- Funciones RPC transaccionales para la gestion del Bono por un superadmin.
--   * restablecer_bono(target_user_id): fija el Saldo_De_Clases del Usuario
--     objetivo en 10 (Req 6.5).
--   * ajustar_bono(target_user_id, valor): fija el Saldo_De_Clases en `valor`,
--     validando que 0 <= valor <= 10 (Req 6.6).
-- Ambas son SECURITY DEFINER y validan es_superadmin() antes de actuar, de modo
-- que la autorizacion critica ocurre en el backend aunque el cliente la omita
-- (Req 5.4). Se usa RAISE EXCEPTION USING ERRCODE/MESSAGE para senalar las
-- condiciones de negocio, acorde a la estrategia de Error Handling del diseno.
-- La modificacion del saldo nunca ocurre por UPDATE directo del cliente: solo a
-- traves de estas RPC (el trigger profiles_inmutabilidad_columnas lo refuerza).
-- _Requirements: 4.1, 6.5, 6.6_
-- _Design: Servicio_Bono; Funciones RPC del backend_

-- =====================================================================
-- Funcion: restablecer_bono(target_user_id)
-- Valida que el llamante sea superadmin y fija el saldo del Usuario objetivo
-- en 10 (bono completo). Rechaza con error de autorizacion insuficiente si el
-- llamante no es superadmin (Req 5.4, 6.5).
-- SECURITY DEFINER + search_path fijo: la escritura corre con los privilegios
-- del propietario de la funcion y evita que la RLS o un search_path manipulado
-- alteren el comportamiento.
-- =====================================================================
create or replace function public.restablecer_bono(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Autorizacion: solo un superadministrador puede restablecer bonos (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Fija el saldo en 10 (bono completo) para el usuario objetivo (Req 6.5).
    update public.profiles
       set saldo_clases = 10
     where id = target_user_id;

    -- Si el usuario objetivo no existe, se informa como dato no encontrado.
    if not found then
        raise exception 'Usuario no encontrado'
            using errcode = 'P0002';
    end if;
end;
$$;

-- =====================================================================
-- Funcion: ajustar_bono(target_user_id, valor)
-- Valida que el llamante sea superadmin y que 0 <= valor <= 10; fija el saldo
-- del Usuario objetivo en `valor`. Rechaza fuera de rango o sin autorizacion
-- sin modificar el saldo (Req 6.6).
-- =====================================================================
create or replace function public.ajustar_bono(target_user_id uuid, valor int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Autorizacion: solo un superadministrador puede ajustar bonos (Req 5.4).
    if not public.es_superadmin() then
        raise exception 'No autorizado: se requiere rol de superadministrador'
            using errcode = '42501';
    end if;

    -- Validacion de rango: el saldo debe permanecer en 0..10 (Req 4.4, 6.6).
    if valor < 0 or valor > 10 then
        raise exception 'El valor del bono debe estar entre 0 y 10'
            using errcode = '22003';
    end if;

    -- Fija el saldo en el valor indicado para el usuario objetivo (Req 6.6).
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
-- Permisos de ejecucion
-- Se concede EXECUTE al rol authenticated; la autorizacion fina (superadmin)
-- se comprueba dentro del cuerpo de cada funcion. El rol anon no recibe
-- permiso: sin sesion no hay acceso (Req 7.3).
-- =====================================================================
grant execute on function public.restablecer_bono(uuid) to authenticated;
grant execute on function public.ajustar_bono(uuid, int) to authenticated;
