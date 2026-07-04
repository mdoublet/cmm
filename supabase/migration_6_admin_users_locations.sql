-- ============================================================================
-- Migration 6 : admin - liste utilisateurs avec stats + gestion lieux officiels
-- A exécuter dans le SQL Editor de Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC : liste de tous les invités avec leurs statistiques de trajets
-- ----------------------------------------------------------------------------
create or replace function list_all_guests_admin(p_admin_id uuid)
returns table(
  id uuid,
  first_name text,
  last_name text,
  email text,
  phone text,
  has_vehicle boolean,
  vehicle_seats integer,
  is_admin boolean,
  nb_requests bigint,
  nb_driving bigint
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;

  return query
    select
      g.id,
      g.first_name,
      g.last_name,
      g.email,
      g.phone,
      g.has_vehicle,
      g.vehicle_seats,
      g.is_admin,
      (select count(*) from ride_requests r where r.requester_id = g.id and r.status <> 'cancelled') as nb_requests,
      (select count(*) from ride_requests r where r.driver_id = g.id and r.status <> 'cancelled') as nb_driving
    from guests g
    order by g.last_name, g.first_name;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : ajouter un lieu officiel (sort_order configurable, < 99)
-- ----------------------------------------------------------------------------
create or replace function admin_add_location(p_admin_id uuid, p_name text, p_sort_order integer default 50)
returns table(id uuid, name text, sort_order integer)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text;
  v_id uuid;
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;
  v_name := trim(p_name);
  if v_name = '' or v_name is null then
    raise exception 'invalid_name';
  end if;
  if exists (select 1 from locations l where lower(l.name) = lower(v_name)) then
    raise exception 'name_already_exists';
  end if;
  insert into locations (name, sort_order)
  values (v_name, p_sort_order)
  returning locations.id into v_id;
  return query select l.id, l.name, l.sort_order from locations l where l.id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : renommer un lieu (admin seulement)
-- ----------------------------------------------------------------------------
create or replace function admin_rename_location(p_admin_id uuid, p_location_id uuid, p_name text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text;
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;
  v_name := trim(p_name);
  if v_name = '' or v_name is null then
    raise exception 'invalid_name';
  end if;
  update locations set name = v_name where id = p_location_id;
  if not found then
    raise exception 'location_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : promouvoir un lieu utilisateur en lieu officiel (sort_order < 99)
-- ----------------------------------------------------------------------------
create or replace function admin_set_location_order(p_admin_id uuid, p_location_id uuid, p_sort_order integer)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;
  update locations set sort_order = p_sort_order where id = p_location_id;
  if not found then
    raise exception 'location_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : supprimer un lieu sans trajets associés (admin seulement)
-- ----------------------------------------------------------------------------
create or replace function admin_delete_location(p_admin_id uuid, p_location_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;
  if exists (
    select 1 from ride_requests
    where departure_location_id = p_location_id or arrival_location_id = p_location_id
  ) then
    raise exception 'location_in_use';
  end if;
  delete from locations where id = p_location_id;
  if not found then
    raise exception 'location_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : liste de tous les lieux (admin, avec sort_order)
-- ----------------------------------------------------------------------------
create or replace function list_all_locations_admin(p_admin_id uuid)
returns table(id uuid, name text, sort_order integer)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests where id = p_admin_id and is_admin) then
    raise exception 'not_authorized';
  end if;
  return query select l.id, l.name, l.sort_order from locations l order by l.sort_order, l.name;
end;
$$;
