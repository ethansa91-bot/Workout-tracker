-- Cheap "is remote ahead of me" check: one round trip returns the latest updated_at
-- per table instead of the app having to query every table individually.

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
  union all select 'workout_blocks', max(updated_at) from public.workout_blocks
  union all select 'time_block_steps', max(updated_at) from public.time_block_steps
  union all select 'rep_block_exercises', max(updated_at) from public.rep_block_exercises
  union all select 'workout_sessions', max(updated_at) from public.workout_sessions
  union all select 'step_logs', max(updated_at) from public.step_logs
  union all select 'set_logs', max(updated_at) from public.set_logs;
$$;
