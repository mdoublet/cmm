-- ============================================================================
-- Migration 3 : auto-inscription + modification du profil + changement de code
-- A exécuter dans le SQL Editor de Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC : inscription d'un nouvel invité (auto-enregistrement)
-- Retourne les infos de session si tout s'est bien passé.
-- ----------------------------------------------------------------------------
create or replace function register_guest(
  p_email     text,
  p_first_name text,
  p_last_name  text,
  p_phone      text,
  p_has_vehicle boolean,
  p_code       text
)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean, is_admin boolean)
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

  insert into guests (first_name, last_name, email, phone, has_vehicle, pin_hash)
  values (
    trim(p_first_name), trim(p_last_name),
    lower(trim(p_email)),
    nullif(trim(p_phone), ''),
    coalesce(p_has_vehicle, false),
    crypt(p_code, gen_salt('bf'))
  )
  returning id into v_id;

  return query
    select g.id, g.first_name, g.last_name, g.has_vehicle, g.is_admin
    from guests g where g.id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : mise à jour du profil (nom, prénom, téléphone, email, véhicule)
-- ----------------------------------------------------------------------------
create or replace function update_guest_profile(
  p_guest_id   uuid,
  p_first_name text,
  p_last_name  text,
  p_phone      text,
  p_email      text,
  p_has_vehicle boolean
)
returns table(first_name text, last_name text, phone text, email text, has_vehicle boolean)
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
  -- vérifier que l'email n'est pas déjà utilisé par quelqu'un d'autre
  if exists (
    select 1 from guests
    where lower(email) = lower(p_email) and id <> p_guest_id
  ) then
    raise exception 'email_already_used';
  end if;

  update guests
  set
    first_name  = trim(p_first_name),
    last_name   = trim(p_last_name),
    phone       = nullif(trim(p_phone), ''),
    email       = lower(trim(p_email)),
    has_vehicle = coalesce(p_has_vehicle, false)
  where id = p_guest_id;

  if not found then
    raise exception 'guest_not_found';
  end if;

  return query
    select g.first_name, g.last_name, g.phone, g.email, g.has_vehicle
    from guests g where g.id = p_guest_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : changement de code PIN (vérifie l'ancien avant de mettre à jour)
-- ----------------------------------------------------------------------------
create or replace function change_guest_pin(
  p_guest_id uuid,
  p_old_code text,
  p_new_code text
)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_hash text;
begin
  if p_new_code is null or length(p_new_code) <> 6 or p_new_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_code';
  end if;

  select pin_hash into v_hash from guests where id = p_guest_id;
  if v_hash is null then
    raise exception 'guest_not_found';
  end if;
  if crypt(p_old_code, v_hash) <> v_hash then
    raise exception 'invalid_old_code';
  end if;

  update guests set pin_hash = crypt(p_new_code, gen_salt('bf')) where id = p_guest_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : récupérer les infos complètes du profil (pour affichage dans l'app)
-- ----------------------------------------------------------------------------
create or replace function get_guest_profile(p_guest_id uuid)
returns table(first_name text, last_name text, email text, phone text, has_vehicle boolean, is_admin boolean)
language sql security definer set search_path = public, extensions as $$
  select g.first_name, g.last_name, g.email, g.phone, g.has_vehicle, g.is_admin
  from guests g where g.id = p_guest_id;
$$;
