-- Migration: 0018_bono_inicial_cero.sql
-- Feature: gym-management-app (Olympus)
--
-- Las cuentas nuevas empiezan con el bono VACÍO (saldo_clases = 0) en lugar de
-- con 10 clases. El gimnasio carga el bono cuando el socio paga, con las
-- funciones de administración que ya existen: `restablecer_bono` (lo deja en
-- 10) o `ajustar_bono` (cualquier valor de 0 a 10).
--
-- Motivo: con el bono inicial de 10, borrar la cuenta y volver a registrarse
-- con el mismo correo daba 10 clases gratis cada vez.
--
-- Solo afecta a los registros a partir de ahora: no modifica el saldo de
-- ninguna cuenta existente. El rango 0..10 del bono no cambia.
-- Sustituye a la regla anterior (migraciones 0001 y 0002, Req 1.2).

-- Valor por defecto de la columna, por si alguna vía crea perfiles sin
-- indicar el saldo.
alter table public.profiles alter column saldo_clases set default 0;

-- Trigger de alta: igual que en 0002, pero con el bono a 0.
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
        0,          -- bono vacío hasta que el socio pague (Req 1.2)
        'activo'    -- estado inicial (Req 1.1)
    );
    return new;
end;
$$;
