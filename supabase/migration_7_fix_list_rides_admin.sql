-- ============================================================================
-- Migration 7 : recréation de list_all_rides_admin
-- À exécuter si l'onglet Admin affiche une erreur 400.
-- ============================================================================

drop function if exists list_all_rides_admin(uuid);

create or replace function list_all_rides_admin(p_admin_id uuid)
returns table(
  id uuid,
  ride_date date,
  ride_time time,
  departure_name text,
  arrival_name text,
  nb_persons integer,
  has_luggage boolean,
  status text,
  driver_comment text,
  requester_first_name text,
  requester_last_name text,
  requester_phone text,
  requester_email text,
  driver_first_name text,
  driver_last_name text,
  driver_phone text
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;

  return query
    select
      r.id,
      r.ride_date,
      r.ride_time,
      coalesce(dl.name, r.departure_custom, '?') as departure_name,
      coalesce(al.name, r.arrival_custom, '?') as arrival_name,
      r.nb_persons,
      r.has_luggage,
      r.status,
      r.driver_comment,
      req.first_name,
      req.last_name,
      req.phone,
      req.email,
      drv.first_name,
      drv.last_name,
      drv.phone
    from ride_requests r
    left join locations dl on dl.id = r.departure_location_id
    left join locations al on al.id = r.arrival_location_id
    join guests req on req.id = r.requester_id
    left join guests drv on drv.id = r.driver_id
    order by r.ride_date, r.ride_time;
end;
$$;
