-- Row Level Security — single implicit user, no Supabase Auth.
--
-- There is no auth.uid() to scope policies to, so every table gets RLS enabled with a
-- permissive "using (true) with check (true)" policy. This is NOT real access control —
-- the table is only as safe as the anon key. It's still turned on (rather than leaving
-- RLS off entirely) so that a leaked anon key at minimum requires guessing schema/table
-- names, and so RLS remains the single toggle point if real auth is ever added later.

alter table public.muscle_categories enable row level security;
create policy "permissive_all" on public.muscle_categories for all using (true) with check (true);

alter table public.muscles enable row level security;
create policy "permissive_all" on public.muscles for all using (true) with check (true);

alter table public.muscle_muscle_categories enable row level security;
create policy "permissive_all" on public.muscle_muscle_categories for all using (true) with check (true);

alter table public.equipment enable row level security;
create policy "permissive_all" on public.equipment for all using (true) with check (true);

alter table public.weight_combos enable row level security;
create policy "permissive_all" on public.weight_combos for all using (true) with check (true);

alter table public.exercise_categories enable row level security;
create policy "permissive_all" on public.exercise_categories for all using (true) with check (true);

alter table public.exercises enable row level security;
create policy "permissive_all" on public.exercises for all using (true) with check (true);

alter table public.exercise_muscles enable row level security;
create policy "permissive_all" on public.exercise_muscles for all using (true) with check (true);

alter table public.exercise_exercise_categories enable row level security;
create policy "permissive_all" on public.exercise_exercise_categories for all using (true) with check (true);

alter table public.workouts enable row level security;
create policy "permissive_all" on public.workouts for all using (true) with check (true);

alter table public.workout_blocks enable row level security;
create policy "permissive_all" on public.workout_blocks for all using (true) with check (true);

alter table public.time_block_steps enable row level security;
create policy "permissive_all" on public.time_block_steps for all using (true) with check (true);

alter table public.rep_block_exercises enable row level security;
create policy "permissive_all" on public.rep_block_exercises for all using (true) with check (true);

alter table public.workout_sessions enable row level security;
create policy "permissive_all" on public.workout_sessions for all using (true) with check (true);

alter table public.step_logs enable row level security;
create policy "permissive_all" on public.step_logs for all using (true) with check (true);

alter table public.set_logs enable row level security;
create policy "permissive_all" on public.set_logs for all using (true) with check (true);
