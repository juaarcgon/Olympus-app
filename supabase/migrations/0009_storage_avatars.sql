-- Migration: 0009_storage_avatars.sql
-- Feature: gym-management-app (Olympus)
-- Crea el bucket de Storage `avatars` y sus politicas RLS de forma que:
--   * Lectura publica de las fotos de perfil (el cliente usa getPublicUrl),
--     coherente con el uso actual del datasource (profile_remote_datasource).
--   * Cada Usuario autenticado solo puede SUBIR / ACTUALIZAR / BORRAR objetos
--     dentro de SU PROPIA carpeta `<auth.uid()>/...`. Asi un usuario no puede
--     sobrescribir ni borrar el avatar de otro (aislamiento por carpeta).
--
-- Contexto: el cliente guarda el avatar en la ruta `<userId>/avatar<ext>` con
-- upsert (ver ProfileRemoteDataSource.uploadAvatar). La primera componente de
-- la ruta (storage.foldername(name))[1] es el id del propietario, que debe
-- coincidir con auth.uid().
--
-- Esta migracion es aditiva: NO modifica tablas, triggers ni politicas de
-- 0001-0008. Opera sobre el esquema `storage` gestionado por Supabase.
-- _Requirements: 1.7, 3.2, 7.2, 7.3_
-- _Design: Supabase Storage; Security and RLS Strategy_

-- =====================================================================
-- Bucket `avatars` (publico para lectura).
-- `public = true` habilita getPublicUrl; la ESCRITURA sigue restringida por
-- las politicas de abajo (lectura publica != escritura publica).
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- =====================================================================
-- Politicas RLS sobre storage.objects para el bucket `avatars`.
-- RLS ya esta activado por Supabase en storage.objects.
-- =====================================================================

-- Lectura publica: cualquiera puede descargar un avatar por su URL publica.
drop policy if exists avatars_select_public on storage.objects;
create policy avatars_select_public
    on storage.objects
    for select
    to public
    using (bucket_id = 'avatars');

-- Subida: un usuario autenticado solo puede crear objetos cuya carpeta raiz
-- sea su propio id (`<auth.uid()>/...`).
drop policy if exists avatars_insert_own on storage.objects;
create policy avatars_insert_own
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Actualizacion (upsert reemplaza el avatar anterior): solo sobre objetos de
-- su propia carpeta.
drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own
    on storage.objects
    for update
    to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Borrado: solo sobre objetos de su propia carpeta.
drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
