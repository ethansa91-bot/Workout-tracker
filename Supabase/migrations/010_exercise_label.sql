-- Preserves a user's own nickname for an exercise (e.g. from a personal workout
-- log) separately from the catalog `name`, mainly used when a personal exercise
-- gets merged into a matching catalog exercise and the original name would
-- otherwise be lost.

alter table public.exercises
  add column if not exists label text;
