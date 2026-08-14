-- Scheduled workouts: a one-off dated entry, or occurrences generated from a
-- weekly recurring pattern. `recurring_workout_schedules` is the weekly template;
-- `scheduled_workouts` is every concrete dated entry (one-off or generated).

create table if not exists public.recurring_workout_schedules (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid references public.workouts(id),
  weekdays integer[] not null,
  end_date date not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index on public.recurring_workout_schedules (updated_at);
create index on public.recurring_workout_schedules (workout_id);

alter table public.recurring_workout_schedules enable row level security;
create policy "permissive_all" on public.recurring_workout_schedules for all using (true) with check (true);

create table if not exists public.scheduled_workouts (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid references public.workouts(id),
  date date not null,
  recurring_schedule_id uuid references public.recurring_workout_schedules(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index on public.scheduled_workouts (updated_at);
create index on public.scheduled_workouts (workout_id);
create index on public.scheduled_workouts (recurring_schedule_id);

alter table public.scheduled_workouts enable row level security;
create policy "permissive_all" on public.scheduled_workouts for all using (true) with check (true);
