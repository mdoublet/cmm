-- ============================================================================
-- Migration 11 : gestion des invités par l'admin
-- À exécuter dans le SQL Editor de Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC : supprimer un invité (admin)
-- Supprime aussi en cascade ses ride_requests et son rsvp.
-- ----------------------------------------------------------------------------
create or replace function admin_delete_guest(p_admin_id uuid, p_target_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  if p_target_id = p_admin_id then
    raise exception 'cannot_delete_self';
  end if;
  delete from guests where id = p_target_id;
  if not found then raise exception 'guest_not_found'; end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : modifier les infos d'un invité (admin)
-- ----------------------------------------------------------------------------
create or replace function admin_update_guest(
  p_admin_id      uuid,
  p_target_id     uuid,
  p_first_name    text,
  p_last_name     text,
  p_email         text,
  p_phone         text default null,
  p_has_vehicle   boolean default false,
  p_vehicle_seats integer default null,
  p_is_admin      boolean default false
)
returns table(
  guest_id      uuid,
  first_name    text,
  last_name     text,
  email         text,
  phone         text,
  has_vehicle   boolean,
  vehicle_seats integer,
  is_admin      boolean
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  if p_first_name is null or trim(p_first_name) = '' then
    raise exception 'invalid_first_name';
  end if;
  if p_last_name is null or trim(p_last_name) = '' then
    raise exception 'invalid_last_name';
  end if;
  if p_email is not null and p_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    raise exception 'invalid_email';
  end if;
  if p_email is not null and exists (
    select 1 from guests g where lower(g.email) = lower(p_email) and g.id <> p_target_id
  ) then
    raise exception 'email_already_used';
  end if;

  update guests g set
    first_name    = trim(p_first_name),
    last_name     = trim(p_last_name),
    email         = case when p_email is not null then lower(trim(p_email)) else g.email end,
    phone         = nullif(trim(coalesce(p_phone, '')), ''),
    has_vehicle   = coalesce(p_has_vehicle, false),
    vehicle_seats = case when coalesce(p_has_vehicle, false) then p_vehicle_seats else null end,
    is_admin      = coalesce(p_is_admin, false)
  where g.id = p_target_id;

  if not found then raise exception 'guest_not_found'; end if;

  return query
    select g2.id, g2.first_name, g2.last_name, g2.email, g2.phone,
           g2.has_vehicle, g2.vehicle_seats, g2.is_admin
    from guests g2 where g2.id = p_target_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : réinitialiser le PIN d'un invité (admin)
-- ----------------------------------------------------------------------------
create or replace function admin_reset_guest_pin(p_admin_id uuid, p_target_id uuid, p_new_code text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;
  if p_new_code is null or p_new_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_code';
  end if;
  update guests set pin_hash = crypt(p_new_code, gen_salt('bf')) where id = p_target_id;
  if not found then raise exception 'guest_not_found'; end if;
end;
$$;
