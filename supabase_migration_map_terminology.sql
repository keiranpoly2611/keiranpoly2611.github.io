-- FS25 Maps - Rename "room" to "map" in user-facing error text
-- Run this once, in a NEW query, in the SAME Supabase project. Purely cosmetic -
-- same table, same columns, same logic, only the text shown in error messages
-- changes (the UI already says "Map code" / "Create a new map" etc).

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
    raise exception 'Wrong edit code, or that map does not exist yet';
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
    raise exception 'Wrong edit code, or that map does not exist yet - create it first';
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
    raise exception 'Map code cannot be blank';
  end if;
  if p_code is null or length(p_code) = 0 then
    raise exception 'Choose an edit code (password) for this map';
  end if;
  if exists (select 1 from map_saves where map_id = p_map_id and room_code = v_room) then
    raise exception 'That map code is already taken - pick another one';
  end if;

  insert into map_saves (map_id, room_code, access_code, data, updated_at, updated_by)
  values (p_map_id, v_room, p_code, null, v_created_at, p_created_by);

  return query select v_created_at;
end;
$$;
