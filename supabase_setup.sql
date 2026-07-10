-- FS25 Maps - Universal Cloud Sync backend (Supabase)
-- Run this once, in full, in a NEW Supabase project's SQL Editor.
-- (If you already ran an older version of this file, use the migration
-- scripts instead - don't re-run this one.)
--
-- Supports public "rooms": anyone can create their own private room per map
-- via the map's "Create a new room" button (own room code + own edit code),
-- then share both with their friends to sync together. Leaving the room code
-- blank on the Load/Upload controls uses each map's default room.

create table if not exists public.map_saves (
  map_id text not null,
  room_code text not null default '',
  access_code text not null,
  data jsonb,
  updated_at timestamptz,
  updated_by text,
  primary key (map_id, room_code)
);

alter table public.map_saves enable row level security;
-- No policies are created on purpose: with RLS on and zero policies, PostgREST
-- (the anon/authenticated roles) cannot read or write this table directly at all.
-- The only way in is through the functions below, which check the shared
-- edit code themselves before touching any row.
revoke all on public.map_saves from anon, authenticated;

create or replace function public.fs25_load_map(p_map_id text, p_code text, p_room_code text default '')
returns table(data jsonb, updated_at timestamptz, updated_by text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room text := coalesce(p_room_code, '');
begin
  if not exists (
    select 1 from map_saves m
    where m.map_id = p_map_id and m.room_code = v_room and m.access_code = p_code
  ) then
    raise exception 'Wrong edit code, or that room does not exist yet';
  end if;

  return query
  select m.data, m.updated_at, m.updated_by
  from map_saves m
  where m.map_id = p_map_id and m.room_code = v_room;
end;
$$;

create or replace function public.fs25_save_map(p_map_id text, p_code text, p_data jsonb, p_updated_by text, p_room_code text default '')
returns table(saved_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room text := coalesce(p_room_code, '');
  v_saved_at timestamptz;
begin
  if not exists (
    select 1 from map_saves where map_id = p_map_id and room_code = v_room and access_code = p_code
  ) then
    raise exception 'Wrong edit code, or that room does not exist yet - create it first';
  end if;

  update map_saves
  set data = p_data, updated_at = now(), updated_by = p_updated_by
  where map_id = p_map_id and room_code = v_room
  returning updated_at into v_saved_at;

  return query select v_saved_at;
end;
$$;

create or replace function public.fs25_create_room(p_map_id text, p_room_code text, p_code text, p_created_by text default '')
returns table(created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room text := coalesce(p_room_code, '');
  v_created_at timestamptz := now();
begin
  if v_room = '' then
    raise exception 'Room code cannot be blank';
  end if;
  if p_code is null or length(p_code) = 0 then
    raise exception 'Choose an edit code (password) for this room';
  end if;
  if exists (select 1 from map_saves where map_id = p_map_id and room_code = v_room) then
    raise exception 'That room code is already taken - pick another one';
  end if;

  insert into map_saves (map_id, room_code, access_code, data, updated_at, updated_by)
  values (p_map_id, v_room, p_code, null, v_created_at, p_created_by);

  return query select v_created_at;
end;
$$;

grant execute on function public.fs25_load_map(text, text, text) to anon, authenticated;
grant execute on function public.fs25_save_map(text, text, jsonb, text, text) to anon, authenticated;
grant execute on function public.fs25_create_room(text, text, text, text) to anon, authenticated;

-- Seed the default room for each of the 4 built-in maps.
insert into public.map_saves (map_id, room_code, access_code, data, updated_at, updated_by) values
  ('kinlaig', '', 'Bubblegum1', null, null, null),
  ('zielonka', '', 'Bubblegum1', null, null, null),
  ('hutanpantai', '', 'Bubblegum1', null, null, null),
  ('riverbendsprings', '', 'Bubblegum1', null, null, null)
on conflict (map_id, room_code) do nothing;
