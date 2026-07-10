-- FS25 Maps - Universal Cloud Sync backend (Supabase)
-- Run this once, in full, in your Supabase project's SQL Editor.
-- Replaces the separate Google Apps Script deployment each map used to need.

create table if not exists public.map_saves (
  map_id text primary key,
  access_code text not null,
  data jsonb,
  updated_at timestamptz,
  updated_by text
);

alter table public.map_saves enable row level security;
-- No policies are created on purpose: with RLS on and zero policies, PostgREST
-- (the anon/authenticated roles) cannot read or write this table directly at all.
-- The only way in is through the two functions below, which check the shared
-- edit code themselves before touching any row.
revoke all on public.map_saves from anon, authenticated;

create or replace function public.fs25_load_map(p_map_id text, p_code text)
returns table(data jsonb, updated_at timestamptz, updated_by text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from map_saves m where m.map_id = p_map_id and m.access_code = p_code
  ) then
    raise exception 'Wrong edit code';
  end if;

  return query
  select m.data, m.updated_at, m.updated_by
  from map_saves m
  where m.map_id = p_map_id;
end;
$$;

create or replace function public.fs25_save_map(p_map_id text, p_code text, p_data jsonb, p_updated_by text)
returns table(saved_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saved_at timestamptz;
begin
  if not exists (
    select 1 from map_saves m where m.map_id = p_map_id and m.access_code = p_code
  ) then
    raise exception 'Wrong edit code';
  end if;

  update map_saves
  set data = p_data, updated_at = now(), updated_by = p_updated_by
  where map_id = p_map_id
  returning updated_at into v_saved_at;

  return query select v_saved_at;
end;
$$;

grant execute on function public.fs25_load_map(text, text) to anon, authenticated;
grant execute on function public.fs25_save_map(text, text, jsonb, text) to anon, authenticated;

-- Seed one row per map, keeping the same shared edit code everyone already
-- uses today so no one has to learn a new password.
insert into public.map_saves (map_id, access_code, data, updated_at, updated_by) values
  ('kinlaig', 'Bubblegum1', null, null, null),
  ('zielonka', 'Bubblegum1', null, null, null),
  ('hutanpantai', 'Bubblegum1', null, null, null),
  ('riverbendsprings', 'Bubblegum1', null, null, null)
on conflict (map_id) do nothing;
