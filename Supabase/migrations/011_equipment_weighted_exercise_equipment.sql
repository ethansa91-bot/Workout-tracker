-- Splits equipment into passive vs. weighted (adjustable-weight) via `is_weighted`,
-- and replaces the single `exercises.equipment_id` FK with a many-to-many
-- `exercise_equipment` join table so an exercise can reference multiple equipment
-- items across both categories. `exercises.equipment_id` is left in place, unused
-- going forward, rather than dropped — same approach as `equipment.is_favorited`
-- in 007. Also adds a description to workout_sections (used by section templates).

alter table public.equipment
  add column if not exists is_weighted boolean not null default false;

alter table public.workout_sections
  add column if not exists description text;

create table if not exists public.exercise_equipment (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises(id),
  equipment_id uuid not null references public.equipment(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (exercise_id, equipment_id)
);

-- Same permissive RLS as every other table (002_rls.sql) — no Supabase Auth in use.
alter table public.exercise_equipment enable row level security;
create policy "permissive_all" on public.exercise_equipment for all using (true) with check (true);

-- Server-authoritative updated_at (003_triggers.sql).
create trigger trg_exercise_equipment_updated_at before insert or update on public.exercise_equipment
  for each row execute function public.set_updated_at();

-- Rebuild sync_watermarks() (004_sync_watermarks.sql, last redefined in 009) to
-- include the new join table.
create or replace function public.sync_watermarks()
returns table(table_name text, max_updated_at timestamptz)
language sql stable as $$
  select 'muscle_categories', max(updated_at) from public.muscle_categories
  union all select 'muscles', max(updated_at) from public.muscles
  union all select 'muscle_muscle_categories', max(updated_at) from public.muscle_muscle_categories
  union all select 'equipment', max(updated_at) from public.equipment
  union all select 'weight_combos', max(updated_at) from public.weight_combos
  union all select 'exercise_categories', max(updated_at) from public.exercise_categories
  union all select 'exercises', max(updated_at) from public.exercises
  union all select 'exercise_muscles', max(updated_at) from public.exercise_muscles
  union all select 'exercise_exercise_categories', max(updated_at) from public.exercise_exercise_categories
  union all select 'exercise_equipment', max(updated_at) from public.exercise_equipment
  union all select 'workouts', max(updated_at) from public.workouts
  union all select 'workout_sections', max(updated_at) from public.workout_sections
  union all select 'time_section_steps', max(updated_at) from public.time_section_steps
  union all select 'rep_section_exercises', max(updated_at) from public.rep_section_exercises
  union all select 'workout_sessions', max(updated_at) from public.workout_sessions
  union all select 'step_logs', max(updated_at) from public.step_logs
  union all select 'set_logs', max(updated_at) from public.set_logs;
$$;
