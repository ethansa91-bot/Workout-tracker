-- Server-authoritative updated_at.
--
-- The client never gets to set updated_at directly — this trigger stamps it from the
-- database clock on every insert/update. That's what makes the sync engine's
-- last-write-wins conflict resolution safe: arbitration is based on server receive
-- order, not each device's local clock (which could be skewed).

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_muscle_categories_updated_at before insert or update on public.muscle_categories
  for each row execute function public.set_updated_at();
create trigger trg_muscles_updated_at before insert or update on public.muscles
  for each row execute function public.set_updated_at();
create trigger trg_muscle_muscle_categories_updated_at before insert or update on public.muscle_muscle_categories
  for each row execute function public.set_updated_at();
create trigger trg_equipment_updated_at before insert or update on public.equipment
  for each row execute function public.set_updated_at();
create trigger trg_weight_combos_updated_at before insert or update on public.weight_combos
  for each row execute function public.set_updated_at();
create trigger trg_exercise_categories_updated_at before insert or update on public.exercise_categories
  for each row execute function public.set_updated_at();
create trigger trg_exercises_updated_at before insert or update on public.exercises
  for each row execute function public.set_updated_at();
create trigger trg_exercise_muscles_updated_at before insert or update on public.exercise_muscles
  for each row execute function public.set_updated_at();
create trigger trg_exercise_exercise_categories_updated_at before insert or update on public.exercise_exercise_categories
  for each row execute function public.set_updated_at();
create trigger trg_workouts_updated_at before insert or update on public.workouts
  for each row execute function public.set_updated_at();
create trigger trg_workout_blocks_updated_at before insert or update on public.workout_blocks
  for each row execute function public.set_updated_at();
create trigger trg_time_block_steps_updated_at before insert or update on public.time_block_steps
  for each row execute function public.set_updated_at();
create trigger trg_rep_block_exercises_updated_at before insert or update on public.rep_block_exercises
  for each row execute function public.set_updated_at();
create trigger trg_workout_sessions_updated_at before insert or update on public.workout_sessions
  for each row execute function public.set_updated_at();
create trigger trg_step_logs_updated_at before insert or update on public.step_logs
  for each row execute function public.set_updated_at();
create trigger trg_set_logs_updated_at before insert or update on public.set_logs
  for each row execute function public.set_updated_at();
