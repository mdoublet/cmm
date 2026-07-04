-- ============================================================================
-- Migration 4 : vehicle_seats dans register_guest, update_guest_profile,
--               get_guest_profile
-- A exécuter dans le SQL Editor de Supabase.
-- ============================================================================

-- register_guest : ajout p_vehicle_seats
drop function if exists register_guest(text, text, text, text, boolean, text);

create or replace function register_guest(
  p_email        text,
  p_first_name   text,
  p_last_name    text,
  p_phone        text,
  p_has_vehicle  boolean,
  p_vehicle_seats integer,
  p_code         text
)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, vehicle_seats integer, is_admin boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
begin
  if p_code is null or length(p_code) <> 6 or p_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_code';
  end if;
  if p_email is null or p_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    raise exception 'invalid_email';
  end if;
  if p_first_name is null or trim(p_first_name) = '' then
    raise exception 'invalid_first_name';
  end if;
  if p_last_name is null or trim(p_last_name) = '' then
    raise exception 'invalid_last_name';
  end if;
  if exists (select 1 from guests where lower(email) = lower(p_email)) then
    raise exception 'email_already_used';
  end if;

  insert into guests (first_name, last_name, email, phone, has_vehicle, vehicle_seats, pin_hash)
  values (
    trim(p_first_name), trim(p_last_name),
    lower(trim(p_email)),
    nullif(trim(p_phone), ''),
    coalesce(p_has_vehicle, false),
    case when coalesce(p_has_vehicle, false) then p_vehicle_seats else null end,
    crypt(p_code, gen_salt('bf'))
  )
  returning id into v_id;

  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.vehicle_seats, g.is_admin
    from guests g where g.id = v_id;
end;
$$;

-- update_guest_profile : ajout p_vehicle_seats
drop function if exists update_guest_profile(uuid, text, text, text, text, boolean);

create or replace function update_guest_profile(
  p_guest_id     uuid,
  p_first_name   text,
  p_last_name    text,
  p_phone        text,
  p_email        text,
  p_has_vehicle  boolean,
  p_vehicle_seats integer
)
returns table(first_name text, last_name text, phone text, email text, has_vehicle boolean, vehicle_seats integer)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_email is null or p_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    raise exception 'invalid_email';
  end if;
  if p_first_name is null or trim(p_first_name) = '' then
    raise exception 'invalid_first_name';
  end if;
  if p_last_name is null or trim(p_last_name) = '' then
    raise exception 'invalid_last_name';
  end if;
  if exists (
    select 1 from guests
    where lower(email) = lower(p_email) and id <> p_guest_id
  ) then
    raise exception 'email_already_used';
  end if;

  update guests
  set
    first_name    = trim(p_first_name),
    last_name     = trim(p_last_name),
    phone         = nullif(trim(p_phone), ''),
    email         = lower(trim(p_email)),
    has_vehicle   = coalesce(p_has_vehicle, false),
    vehicle_seats = case when coalesce(p_has_vehicle, false) then p_vehicle_seats else null end
  where id = p_guest_id;

  if not found then
    raise exception 'guest_not_found';
  end if;

  return query
    select g.first_name, g.last_name, g.phone, g.email, g.has_vehicle, g.vehicle_seats
    from guests g where g.id = p_guest_id;
end;
$$;

-- get_guest_profile : ajout vehicle_seats
drop function if exists get_guest_profile(uuid);

create or replace function get_guest_profile(p_guest_id uuid)
returns table(first_name text, last_name text, email text, phone text, has_vehicle boolean, vehicle_seats integer, is_admin boolean)
language sql security definer set search_path = public, extensions as $$
  select g.first_name, g.last_name, g.email, g.phone, g.has_vehicle, g.vehicle_seats, g.is_admin
  from guests g where g.id = p_guest_id;
$$;

-- verify_guest_code et set_guest_code : renvoyer aussi vehicle_seats
drop function if exists verify_guest_code(text, text);
drop function if exists set_guest_code(text, text);

create or replace function set_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, vehicle_seats integer, is_admin boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
  v_has_pin boolean;
begin
  if p_code is null or length(p_code) <> 6 or p_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_code';
  end if;
  select id, (pin_hash is not null) into v_id, v_has_pin
  from guests
  where lower(email) = lower(p_identifier) or phone = p_identifier
  limit 1;
  if v_id is null then raise exception 'guest_not_found'; end if;
  if v_has_pin then raise exception 'code_already_set'; end if;
  update guests set pin_hash = crypt(p_code, gen_salt('bf')) where id = v_id;
  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.vehicle_seats, g.is_admin
    from guests g where g.id = v_id;
end;
$$;

create or replace function verify_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, vehicle_seats integer, is_admin boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
  v_hash text;
begin
  select id, pin_hash into v_id, v_hash
  from guests
  where lower(email) = lower(p_identifier) or phone = p_identifier
  limit 1;
  if v_id is null or v_hash is null then raise exception 'guest_not_found'; end if;
  if crypt(p_code, v_hash) <> v_hash then raise exception 'invalid_code'; end if;
  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.vehicle_seats, g.is_admin
    from guests g where g.id = v_id;
end;
$$;
