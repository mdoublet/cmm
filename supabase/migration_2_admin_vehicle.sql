-- ============================================================================
-- Migration 2 : administrateurs + auto-déclaration véhicule
-- A exécuter dans le SQL Editor de Supabase.
-- ============================================================================

alter table guests add column if not exists is_admin boolean not null default false;

-- Pour désigner un administrateur :
-- update guests set is_admin = true where email = 'EMAIL_ADMIN';

-- ----------------------------------------------------------------------------
-- get_guest_status / set_guest_code / verify_guest_code : on renvoie aussi
-- is_admin pour que l'appli sache quel onglet afficher.
-- ----------------------------------------------------------------------------
create or replace function get_guest_status(p_identifier text)
returns table(guest_id uuid, first_name text, last_name text, has_code boolean, has_vehicle boolean, is_admin boolean)
language sql security definer set search_path = public, extensions as $$
  select g.id, g.first_name, g.last_name, (g.pin_hash is not null), g.has_vehicle, g.is_admin
  from guests g
  where lower(g.email) = lower(p_identifier) or g.phone = p_identifier
  limit 1;
$$;

create or replace function set_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, is_admin boolean)
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

  if v_id is null then
    raise exception 'guest_not_found';
  end if;
  if v_has_pin then
    raise exception 'code_already_set';
  end if;

  update guests set pin_hash = crypt(p_code, gen_salt('bf')) where id = v_id;

  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.is_admin from guests g where g.id = v_id;
end;
$$;

create or replace function verify_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, is_admin boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
  v_hash text;
begin
  select id, pin_hash into v_id, v_hash
  from guests
  where lower(email) = lower(p_identifier) or phone = p_identifier
  limit 1;

  if v_id is null or v_hash is null then
    raise exception 'guest_not_found';
  end if;

  if crypt(p_code, v_hash) <> v_hash then
    raise exception 'invalid_code';
  end if;

  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.is_admin from guests g where g.id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : l'invité déclare lui-même s'il a un véhicule
-- ----------------------------------------------------------------------------
create or replace function update_has_vehicle(p_guest_id uuid, p_has_vehicle boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update guests set has_vehicle = p_has_vehicle where id = p_guest_id;
  if not found then
    raise exception 'guest_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : vue d'ensemble pour les administrateurs
-- ----------------------------------------------------------------------------
create or replace function list_all_rides_admin(p_admin_id uuid)
returns table(
  id uuid, ride_date date, ride_time time,
  departure_name text, arrival_name text,
  nb_persons integer, has_luggage boolean,
  status text, driver_comment text,
  requester_first_name text, requester_last_name text, requester_phone text, requester_email text,
  driver_first_name text, driver_last_name text, driver_phone text
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;

  return query
    select
      r.id, r.ride_date, r.ride_time,
      coalesce(dl.name, r.departure_custom), coalesce(al.name, r.arrival_custom),
      r.nb_persons, r.has_luggage, r.status, r.driver_comment,
      req.first_name, req.last_name, req.phone, req.email,
      drv.first_name, drv.last_name, drv.phone
    from ride_requests r
    left join locations dl on dl.id = r.departure_location_id
    left join locations al on al.id = r.arrival_location_id
    join guests req on req.id = r.requester_id
    left join guests drv on drv.id = r.driver_id
    order by r.ride_date, r.ride_time;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : un administrateur annule un trajet (quel que soit son statut)
-- ----------------------------------------------------------------------------
create or replace function admin_cancel_ride(p_admin_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;

  update ride_requests set status = 'cancelled', updated_at = now() where id = p_ride_id;
  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : un administrateur remet un trajet en attente (retire le chauffeur)
-- ----------------------------------------------------------------------------
create or replace function admin_reset_ride(p_admin_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;

  update ride_requests
  set status = 'pending', driver_id = null, driver_comment = null, updated_at = now()
  where id = p_ride_id;
  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;
