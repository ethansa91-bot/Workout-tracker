-- Renames "block" -> "section" across the workout-authoring tables to match the app's
-- WorkoutBlock -> WorkoutSection model rename, and relaxes workout_sections.workout_id
-- to nullable so a standalone template section (no parent workout) can be synced.
-- Historical migrations 001-008 are not edited; this is additive/renaming only.
-- `rename table`/`rename column` preserve FKs, indexes, RLS policies, and triggers
-- automatically — only the sync_watermarks() function (004) embeds table names as
-- string literals and needs a `create or replace`.

alter table public.workout_blocks rename to workout_sections;
alter table public.workout_sections rename column block_type to section_type;
alter table public.workout_sections alter column workout_id drop not null;

alter table public.time_block_steps rename to time_section_steps;
alter table public.time_section_steps rename column workout_block_id to workout_section_id;

alter table public.rep_block_exercises rename to rep_section_exercises;
alter table public.rep_section_exercises rename column workout_block_id to workout_section_id;

alter table public.workout_sessions rename column current_block_index to current_section_index;

alter table public.step_logs rename column time_block_step_id to time_section_step_id;
alter table public.set_logs rename column rep_block_exercise_id to rep_section_exercise_id;

-- Cosmetic renames so trigger/policy names still describe the table they're on.
alter trigger trg_workout_blocks_updated_at on public.workout_sections rename to trg_workout_sections_updated_at;
alter trigger trg_time_block_steps_updated_at on public.time_section_steps rename to trg_time_section_steps_updated_at;
alter trigger trg_rep_block_exercises_updated_at on public.rep_section_exercises rename to trg_rep_section_exercises_updated_at;

-- Rebuild sync_watermarks() (004_sync_watermarks.sql) against the renamed tables.
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
  union all select 'workouts', max(updated_at) from public.workouts
  union all select 'workout_sections', max(updated_at) from public.workout_sections
  union all select 'time_section_steps', max(updated_at) from public.time_section_steps
  union all select 'rep_section_exercises', max(updated_at) from public.rep_section_exercises
  union all select 'workout_sessions', max(updated_at) from public.workout_sessions
  union all select 'step_logs', max(updated_at) from public.step_logs
  union all select 'set_logs', max(updated_at) from public.set_logs;
$$;
