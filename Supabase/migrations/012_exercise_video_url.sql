-- Adds an optional YouTube link per exercise, shown as a thumbnail/player in the app.

alter table public.exercises
  add column if not exists video_url text;
