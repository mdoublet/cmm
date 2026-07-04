-- ============================================================================
-- Migration 5 : permettre aux utilisateurs d'ajouter leurs propres lieux
-- A exécuter dans le SQL Editor de Supabase.
-- ============================================================================

create or replace function add_location(p_name text)
returns table(id uuid, name text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
  v_name text;
begin
  v_name := trim(p_name);
  if v_name = '' or v_name is null then
    raise exception 'invalid_name';
  end if;

  -- Réutiliser si le lieu existe déjà (insensible à la casse)
  select l.id into v_id from locations l where lower(l.name) = lower(v_name) limit 1;

  if v_id is null then
    insert into locations (name, sort_order)
    values (v_name, 99)
    returning locations.id into v_id;
  end if;

  return query select l.id, l.name from locations l where l.id = v_id;
end;
$$;
