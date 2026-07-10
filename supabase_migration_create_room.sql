-- FS25 Maps - Make "create a room" its own explicit action
-- Run this once, in a NEW query, in the SAME Supabase project (after you've
-- already run supabase_migration_rooms.sql). Safe to run - doesn't touch
-- existing data, just adds one function and changes how fs25_save_map behaves.
--
-- Before this: uploading to a room code that didn't exist yet silently
-- created it - creation was mixed in with normal syncing.
-- After this: rooms must be created explicitly via fs25_create_room. Trying
-- to load/save a room that doesn't exist now gives a clear error telling you
-- to create it first, instead of silently making one.

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

grant execute on function public.fs25_create_room(text, text, text, text) to anon, authenticated;

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

grant execute on function public.fs25_save_map(text, text, jsonb, text, text) to anon, authenticated;
