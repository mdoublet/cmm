-- Correctif : "column reference first_name is ambiguous" dans set_guest_code
-- et verify_guest_code. A exécuter dans le SQL Editor de Supabase.

create or replace function set_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean)
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
    select g.id, g.first_name, g.last_name, g.has_vehicle from guests g where g.id = v_id;
end;
$$;

create or replace function verify_guest_code(p_identifier text, p_code text)
returns table(guest_id uuid, first_name text, last_name text, has_vehicle boolean)
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
    select g.id, g.first_name, g.last_name, g.has_vehicle from guests g where g.id = v_id;
end;
$$;
