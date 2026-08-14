-- Replaces the single "in my equipment" favorite with two independent flags
-- (at home / at the gym), and lets each piece of equipment override the global
-- lb/kg default. `is_favorited` is left in place, unused going forward, rather
-- than dropped — the app backfills is_at_home from it locally before this ships,
-- and dropping the column here isn't needed for that to work.

alter table public.equipment
  add column if not exists is_at_home boolean not null default false,
  add column if not exists is_at_gym boolean not null default false,
  add column if not exists preferred_weight_unit text;
