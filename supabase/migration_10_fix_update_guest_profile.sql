-- ============================================================================
-- Migration 10 : recréation de update_guest_profile avec p_vehicle_seats
-- À exécuter dans le SQL Editor de Supabase si la mise à jour du profil
-- renvoie une erreur 400.
-- ============================================================================

drop function if exists update_guest_profile(uuid, text, text, text, text, boolean);
drop function if exists update_guest_profile(uuid, text, text, text, text, boolean, integer);

create or replace function update_guest_profile(
  p_guest_id      uuid,
  p_first_name    text,
  p_last_name     text,
  p_email         text,
  p_phone         text,
  p_has_vehicle   boolean,
  p_vehicle_seats integer default null
)
returns table(
  first_name    text,
  last_name     text,
  phone         text,
  email         text,
  has_vehicle   boolean,
  vehicle_seats integer
)
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
    select 1 from guests g
    where lower(g.email) = lower(p_email) and g.id <> p_guest_id
  ) then
    raise exception 'email_already_used';
  end if;

  update guests g2
  set
    first_name    = trim(p_first_name),
    last_name     = trim(p_last_name),
    phone         = nullif(trim(coalesce(p_phone, '')), ''),
    email         = lower(trim(p_email)),
    has_vehicle   = coalesce(p_has_vehicle, false),
    vehicle_seats = case when coalesce(p_has_vehicle, false) then p_vehicle_seats else null end
  where g2.id = p_guest_id;

  if not found then raise exception 'guest_not_found'; end if;

  return query
    select g3.first_name, g3.last_name, g3.phone, g3.email, g3.has_vehicle, g3.vehicle_seats
    from guests g3 where g3.id = p_guest_id;
end;
$$;
