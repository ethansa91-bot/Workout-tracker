-- Personal records: one manually-editable record per exercise, independent of
-- session history (either weight x reps, or a max hold time).

create table if not exists public.personal_records (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid references public.exercises(id),
  tracking_mode text not null default 'repsWeight',
  weight double precision,
  reps integer,
  hold_seconds integer,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index on public.personal_records (updated_at);
create index on public.personal_records (exercise_id);

alter table public.personal_records enable row level security;
create policy "permissive_all" on public.personal_records for all using (true) with check (true);
