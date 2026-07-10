-- FS25 Maps - Add public "rooms" to the existing Cloud Sync backend
-- Run this once, in full, in the SAME Supabase project you already set up
-- with supabase_setup.sql. Safe to run even though map_saves already has data -
-- your 4 existing rows become the default room (room_code = '') for each map,
-- so nothing changes for your own group.
--
-- After this, anyone can create their OWN private room per map by simply
-- typing any room code + edit code they like into the Cloud tab and pressing
-- "Upload current map" - that creates the room on the spot. No admin step,
-- no new Supabase setup, nothing for you to do per new group.

alter table public.map_saves add column if not exists room_code text not null default '';

alter table public.map_saves drop constraint if exists map_saves_pkey;
alter table public.map_saves add primary key (map_id, room_code);

drop function if exists public.fs25_load_map(text, text);
drop function if exists public.fs25_save_map(text, text, jsonb, text);

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
  if not exists (select 1 from map_saves where map_id = p_map_id and room_code = v_room) then
    -- Room doesn't exist yet for this map - create it, with the given code
    -- becoming that room's password from now on.
    insert into map_saves (map_id, room_code, access_code, data, updated_at, updated_by)
    values (p_map_id, v_room, p_code, p_data, now(), p_updated_by)
    returning updated_at into v_saved_at;
  else
    if not exists (
      select 1 from map_saves where map_id = p_map_id and room_code = v_room and access_code = p_code
    ) then
      raise exception 'Wrong edit code';
    end if;

    update map_saves
    set data = p_data, updated_at = now(), updated_by = p_updated_by
    where map_id = p_map_id and room_code = v_room
    returning updated_at into v_saved_at;
  end if;

  return query select v_saved_at;
end;
$$;

grant execute on function public.fs25_load_map(text, text, text) to anon, authenticated;
grant execute on function public.fs25_save_map(text, text, jsonb, text, text) to anon, authenticated;
