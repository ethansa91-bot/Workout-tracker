-- Adds max-hold-time tracking mode for By-Reps exercises: a per-exercise mode +
-- head-start seconds, and a nullable hold-duration result on logged sets.

alter table public.rep_block_exercises
  add column if not exists tracking_mode text not null default 'repsWeight',
  add column if not exists head_start_seconds integer not null default 3;

alter table public.set_logs
  add column if not exists hold_seconds integer;
