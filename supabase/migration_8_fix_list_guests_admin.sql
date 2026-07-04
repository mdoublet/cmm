-- ============================================================================
-- Migration 8 : recréation propre de toutes les fonctions admin de migration_6
-- À exécuter dans le SQL Editor de Supabase.
-- ============================================================================

drop function if exists list_all_guests_admin(uuid);
drop function if exists admin_add_location(uuid, text, integer);
drop function if exists admin_rename_location(uuid, uuid, text);
drop function if exists admin_set_location_order(uuid, uuid, integer);
drop function if exists admin_delete_location(uuid, uuid);
drop function if exists list_all_locations_admin(uuid);

-- ----------------------------------------------------------------------------
-- liste tous les invités avec leurs statistiques (réécriture sans sous-requêtes
-- corrélées pour éviter les conflits de types)
-- ----------------------------------------------------------------------------
create or replace function list_all_guests_admin(p_admin_id uuid)
returns table(
  guest_id      uuid,
  first_name    text,
  last_name     text,
  email         text,
  phone         text,
  has_vehicle   boolean,
  vehicle_seats integer,
  is_admin      boolean,
  nb_requests   bigint,
  nb_driving    bigint
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g2 where g2.id = p_admin_id and g2.is_admin) then
    raise exception 'not_authorized';
  end if;

  return query
    select
      g.id                                                                        as guest_id,
      g.first_name,
      g.last_name,
      g.email,
      g.phone,
      g.has_vehicle,
      g.vehicle_seats,
      g.is_admin,
      coalesce(req_stats.cnt, 0)                                                  as nb_requests,
      coalesce(drv_stats.cnt, 0)                                                  as nb_driving
    from guests g
    left join (
      select r.requester_id, count(*) as cnt
      from ride_requests r
      where r.status <> 'cancelled'
      group by r.requester_id
    ) req_stats on req_stats.requester_id = g.id
    left join (
      select r.driver_id, count(*) as cnt
      from ride_requests r
      where r.driver_id is not null and r.status <> 'cancelled'
      group by r.driver_id
    ) drv_stats on drv_stats.driver_id = g.id
    order by g.last_name, g.first_name;
end;
$$;

-- ----------------------------------------------------------------------------
-- ajouter un lieu officiel
-- ----------------------------------------------------------------------------
create or replace function admin_add_location(p_admin_id uuid, p_name text, p_sort_order integer default 50)
returns table(loc_id uuid, loc_name text, loc_sort_order integer)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text;
  v_id uuid;
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  v_name := trim(p_name);
  if v_name = '' or v_name is null then raise exception 'invalid_name'; end if;
  if exists (select 1 from locations l where lower(l.name) = lower(v_name)) then
    raise exception 'name_already_exists';
  end if;
  insert into locations (name, sort_order) values (v_name, p_sort_order) returning locations.id into v_id;
  return query select l.id, l.name, l.sort_order from locations l where l.id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- renommer un lieu
-- ----------------------------------------------------------------------------
create or replace function admin_rename_location(p_admin_id uuid, p_location_id uuid, p_name text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_name text;
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  v_name := trim(p_name);
  if v_name = '' or v_name is null then raise exception 'invalid_name'; end if;
  update locations set name = v_name where id = p_location_id;
  if not found then raise exception 'location_not_found'; end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- changer l'ordre / promouvoir un lieu
-- ----------------------------------------------------------------------------
create or replace function admin_set_location_order(p_admin_id uuid, p_location_id uuid, p_sort_order integer)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  update locations set sort_order = p_sort_order where id = p_location_id;
  if not found then raise exception 'location_not_found'; end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- supprimer un lieu (seulement si non utilisé)
-- ----------------------------------------------------------------------------
create or replace function admin_delete_location(p_admin_id uuid, p_location_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  if exists (
    select 1 from ride_requests r
    where r.departure_location_id = p_location_id or r.arrival_location_id = p_location_id
  ) then
    raise exception 'location_in_use';
  end if;
  delete from locations where id = p_location_id;
  if not found then raise exception 'location_not_found'; end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- liste tous les lieux (admin)
-- ----------------------------------------------------------------------------
create or replace function list_all_locations_admin(p_admin_id uuid)
returns table(loc_id uuid, loc_name text, loc_sort_order integer)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  return query select l.id, l.name, l.sort_order from locations l order by l.sort_order, l.name;
end;
$$;
