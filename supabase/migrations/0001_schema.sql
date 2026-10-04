-- Migration: 0001_schema.sql
-- Feature: gym-management-app (Olympus)
-- Crea las tablas base y constraints: profiles, clases, reservas.
-- Las invariantes criticas (saldo 0..10, aforo 1..10, estados/roles permitidos,
-- unicidad de reservas) se garantizan mediante restricciones de PostgreSQL.
-- _Requirements: 1.1, 1.2, 3.5, 4.4, 5.1, 8.1, 8.6, 8.10, 8.12_
-- _Design: Data Models (tablas profiles, clases, reservas)_

-- Necesario para gen_random_uuid()
create extension if not exists pgcrypto;

-- =====================================================================
-- Tabla profiles (extiende auth.users)
-- Modelo de usuario ampliable: columnas conocidas + metadata JSONB (Req 3.5)
-- =====================================================================
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

-- =====================================================================
-- Tabla clases
-- Sesiones del calendario del gimnasio (Req 8.1)
-- =====================================================================
create table if not exists public.clases (
    id         uuid        primary key default gen_random_uuid(),
    horario    timestamptz not null,
    aforo      int         not null check (aforo between 1 and 10),
    monitor    text        not null,
    created_by uuid        references public.profiles (id),
    created_at timestamptz not null default now()
);

-- =====================================================================
-- Tabla reservas (reserva confirmada + lista de espera unificadas)
-- Una sola fila por par usuario-clase (Req 8.6)
-- =====================================================================
create table if not exists public.reservas (
    id         uuid        primary key default gen_random_uuid(),
    clase_id   uuid        not null references public.clases (id) on delete cascade,
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    status     text        not null check (status in ('confirmada', 'espera')),
    posicion   int         null,
    created_at timestamptz not null default now(),
    unique (clase_id, user_id)
);
