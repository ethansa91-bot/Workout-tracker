-- WorkoutTracker — base schema
-- Run this in the Supabase SQL editor (Project > SQL Editor > New query), in order:
-- 001_schema.sql, 002_rls.sql, 003_triggers.sql, 004_sync_watermarks.sql

create extension if not exists pgcrypto;

-- ===== Catalog =====

create table public.muscle_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.muscles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon_asset_identifier text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.muscle_muscle_categories (
  id uuid primary key default gen_random_uuid(),
  muscle_id uuid not null references public.muscles(id),
  muscle_category_id uuid not null references public.muscle_categories(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (muscle_id, muscle_category_id)
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon_asset_identifier text not null,
  is_custom boolean not null default false,
  is_favorited boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.weight_combos (
  id uuid primary key default gen_random_uuid(),
  equipment_id uuid not null references public.equipment(id),
  value double precision not null,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.exercise_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  notes text,
  icon_asset_identifier text not null,
  is_custom boolean not null default false,
  is_favorited boolean not null default false,
  equipment_id uuid references public.equipment(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.exercise_muscles (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises(id),
  muscle_id uuid not null references public.muscles(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (exercise_id, muscle_id)
);

create table public.exercise_exercise_categories (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises(id),
  exercise_category_id uuid not null references public.exercise_categories(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (exercise_id, exercise_category_id)
);

-- ===== Workout authoring =====

create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  notes text,
  created_at timestamptz not null default now(),
  cloned_from_workout_id uuid references public.workouts(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.workout_blocks (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references public.workouts(id),
  sort_order integer not null,
  block_type text not null check (block_type in ('time', 'rep')),
  name text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.time_block_steps (
  id uuid primary key default gen_random_uuid(),
  workout_block_id uuid not null references public.workout_blocks(id),
  sort_order integer not null,
  step_type text not null check (step_type in ('exercise', 'rest')),
  exercise_id uuid references public.exercises(id),
  duration_seconds integer not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.rep_block_exercises (
  id uuid primary key default gen_random_uuid(),
  workout_block_id uuid not null references public.workout_blocks(id),
  sort_order integer not null,
  exercise_id uuid references public.exercises(id),
  target_sets integer not null,
  custom_rest_seconds integer,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ===== Sessions / logs =====

create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references public.workouts(id),
  status text not null check (status in ('inProgress', 'paused', 'finished', 'abandonedUnfinished')),
  started_at timestamptz not null,
  ended_at timestamptz,
  accumulated_active_seconds double precision not null default 0,
  last_resumed_at timestamptz,
  current_block_index integer not null default 0,
  current_step_index integer,
  current_exercise_index integer,
  current_set_index integer,
  superseded_by_session_id uuid references public.workout_sessions(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.step_logs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions(id),
  time_block_step_id uuid references public.time_block_steps(id),
  step_exercise_name_snapshot text,
  planned_duration_seconds integer not null,
  actual_duration_seconds integer not null,
  outcome text not null check (outcome in ('completed', 'skipped')),
  logged_at timestamptz not null,
  sort_order integer not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Note: sets always use the exercise's assigned equipment (no per-set equipment
-- override), so there is no used_equipment_id column here.
create table public.set_logs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions(id),
  rep_block_exercise_id uuid references public.rep_block_exercises(id),
  exercise_id uuid references public.exercises(id),
  exercise_name_snapshot text,
  set_index integer not null,
  reps integer not null,
  weight double precision not null,
  weight_unit text not null default 'lb',
  logged_at timestamptz not null,
  is_cancelled boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ===== Indexes =====

create index on public.muscles (updated_at);
create index on public.muscle_categories (updated_at);
create index on public.muscle_muscle_categories (updated_at);
create index on public.equipment (updated_at);
create index on public.weight_combos (updated_at);
create index on public.exercise_categories (updated_at);
create index on public.exercises (updated_at);
create index on public.exercise_muscles (updated_at);
create index on public.exercise_exercise_categories (updated_at);
create index on public.workouts (updated_at);
create index on public.workout_blocks (updated_at);
create index on public.time_block_steps (updated_at);
create index on public.rep_block_exercises (updated_at);
create index on public.workout_sessions (updated_at);
create index on public.step_logs (updated_at);
create index on public.set_logs (updated_at);

create index on public.set_logs (exercise_id, logged_at desc)
  where is_cancelled = false and deleted_at is null;
