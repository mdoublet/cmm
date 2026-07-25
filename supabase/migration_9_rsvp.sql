-- ============================================================================
-- Migration 9 : table RSVP + fonctions associées
-- À exécuter dans le SQL Editor de Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table
-- ----------------------------------------------------------------------------
create table if not exists rsvp (
  guest_id       uuid primary key references guests(id) on delete cascade,
  attending      boolean not null default true,
  ceremony       boolean not null default false,
  reception      boolean not null default false,
  lunch_next_day boolean not null default false,
  after_party    boolean not null default false,
  updated_at     timestamptz not null default now()
);

-- Bloquer l'accès direct anonyme (toutes les opérations passent par les RPCs)
alter table rsvp enable row level security;
create policy "no direct access" on rsvp for all to anon using (false);

-- ----------------------------------------------------------------------------
-- RPC : lire son propre RSVP
-- ----------------------------------------------------------------------------
create or replace function get_rsvp(p_guest_id uuid)
returns table(
  attending      boolean,
  ceremony       boolean,
  reception      boolean,
  lunch_next_day boolean,
  after_party    boolean
)
language sql security definer set search_path = public, extensions as $$
  select r.attending, r.ceremony, r.reception, r.lunch_next_day, r.after_party
  from rsvp r
  where r.guest_id = p_guest_id;
$$;

-- ----------------------------------------------------------------------------
-- RPC : créer ou mettre à jour son RSVP
-- ----------------------------------------------------------------------------
create or replace function upsert_rsvp(
  p_guest_id       uuid,
  p_attending      boolean,
  p_ceremony       boolean default false,
  p_reception      boolean default false,
  p_lunch_next_day boolean default false,
  p_after_party    boolean default false
)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_guest_id) then
    raise exception 'guest_not_found';
  end if;

  insert into rsvp (guest_id, attending, ceremony, reception, lunch_next_day, after_party, updated_at)
  values (p_guest_id, p_attending,
    case when p_attending then p_ceremony       else false end,
    case when p_attending then p_reception      else false end,
    case when p_attending then p_lunch_next_day else false end,
    case when p_attending then p_after_party    else false end,
    now()
  )
  on conflict (guest_id) do update set
    attending      = excluded.attending,
    ceremony       = excluded.ceremony,
    reception      = excluded.reception,
    lunch_next_day = excluded.lunch_next_day,
    after_party    = excluded.after_party,
    updated_at     = now();
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : liste de tous les RSVP (admin)
-- ----------------------------------------------------------------------------
create or replace function list_all_rsvp_admin(p_admin_id uuid)
returns table(
  guest_id       uuid,
  first_name     text,
  last_name      text,
  has_answered   boolean,
  attending      boolean,
  ceremony       boolean,
  reception      boolean,
  lunch_next_day boolean,
  after_party    boolean
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from guests g where g.id = p_admin_id and g.is_admin) then
    raise exception 'not_authorized';
  end if;

  return query
    select
      g.id,
      g.first_name,
      g.last_name,
      (r.guest_id is not null)       as has_answered,
      coalesce(r.attending, false)   as attending,
      coalesce(r.ceremony, false)    as ceremony,
      coalesce(r.reception, false)   as reception,
      coalesce(r.lunch_next_day, false) as lunch_next_day,
      coalesce(r.after_party, false) as after_party
    from guests g
    left join rsvp r on r.guest_id = g.id
    order by g.last_name, g.first_name;
end;
$$;
