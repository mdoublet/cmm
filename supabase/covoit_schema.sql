-- ============================================================================
-- Schéma Supabase pour l'application de covoiturage de mariage (covoit.html)
-- Projet : https://ktpiwlcazmodfezrwlqf.supabase.co
--
-- A exécuter dans l'éditeur SQL de Supabase (SQL Editor > New query > Run).
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------------------
-- Table des invités
-- ----------------------------------------------------------------------------
create table if not exists guests (
  id            uuid primary key default gen_random_uuid(),
  first_name    text not null,
  last_name     text not null,
  email         text unique,
  phone         text unique,
  pin_hash      text,                -- code à 6 chiffres, hashé (null = pas encore défini)
  has_vehicle   boolean not null default false,
  vehicle_seats integer,
  created_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- Lieux préconfigurés (départ/arrivée)
-- ----------------------------------------------------------------------------
create table if not exists locations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  sort_order integer not null default 0
);

-- ----------------------------------------------------------------------------
-- Demandes de trajet
-- ----------------------------------------------------------------------------
create table if not exists ride_requests (
  id                  uuid primary key default gen_random_uuid(),
  requester_id        uuid not null references guests(id) on delete cascade,
  ride_date           date not null,
  ride_time           time not null,
  departure_location_id uuid references locations(id),
  departure_custom    text,
  arrival_location_id uuid references locations(id),
  arrival_custom      text,
  nb_persons          integer not null default 1,
  has_luggage         boolean not null default false,
  status              text not null default 'pending'
                        check (status in ('pending','proposed','confirmed','cancelled')),
  driver_id           uuid references guests(id) on delete set null,
  driver_comment      text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_ride_requests_requester on ride_requests(requester_id);
create index if not exists idx_ride_requests_driver on ride_requests(driver_id);
create index if not exists idx_ride_requests_status on ride_requests(status);

-- ----------------------------------------------------------------------------
-- RLS : on bloque tout accès direct depuis le client (anon key).
-- Tout passe par des fonctions RPC "security definer" ci-dessous, qui
-- contrôlent précisément ce qui est lisible/modifiable (pas de PIN ni de
-- coordonnées exposées en dehors du nécessaire).
-- ----------------------------------------------------------------------------
alter table guests enable row level security;
alter table locations enable row level security;
alter table ride_requests enable row level security;

-- lecture publique des lieux (rien de sensible)
drop policy if exists locations_select_all on locations;
create policy locations_select_all on locations for select using (true);

-- aucune policy sur guests / ride_requests => anon n'a aucun accès direct.
-- (les fonctions RPC security definer contournent RLS volontairement)

-- ----------------------------------------------------------------------------
-- RPC : statut d'un invité (a-t-il déjà un code ?) à partir de email/téléphone
-- ----------------------------------------------------------------------------
create or replace function get_guest_status(p_identifier text)
returns table(guest_id uuid, first_name text, last_name text, has_code boolean, has_vehicle boolean)
language sql security definer set search_path = public, extensions as $$
  select id, first_name, last_name, (pin_hash is not null), has_vehicle
  from guests
  where lower(email) = lower(p_identifier) or phone = p_identifier
  limit 1;
$$;

-- ----------------------------------------------------------------------------
-- RPC : définir le code à 6 chiffres (première connexion)
-- ----------------------------------------------------------------------------
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
    select id, first_name, last_name, has_vehicle from guests where id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : vérifier le code lors des connexions suivantes
-- ----------------------------------------------------------------------------
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
    select id, first_name, last_name, has_vehicle from guests where id = v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : créer une demande de trajet
-- ----------------------------------------------------------------------------
create or replace function create_ride_request(
  p_requester_id uuid,
  p_ride_date date,
  p_ride_time time,
  p_departure_location_id uuid,
  p_departure_custom text,
  p_arrival_location_id uuid,
  p_arrival_custom text,
  p_nb_persons integer,
  p_has_luggage boolean
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_ride_id uuid;
begin
  if not exists (select 1 from guests where id = p_requester_id) then
    raise exception 'guest_not_found';
  end if;

  insert into ride_requests(
    requester_id, ride_date, ride_time,
    departure_location_id, departure_custom,
    arrival_location_id, arrival_custom,
    nb_persons, has_luggage
  ) values (
    p_requester_id, p_ride_date, p_ride_time,
    p_departure_location_id, p_departure_custom,
    p_arrival_location_id, p_arrival_custom,
    coalesce(p_nb_persons, 1), coalesce(p_has_luggage, false)
  ) returning id into v_ride_id;

  return v_ride_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : mes demandes (en tant qu'invité demandeur)
-- ----------------------------------------------------------------------------
create or replace function list_my_ride_requests(p_requester_id uuid)
returns table(
  id uuid, ride_date date, ride_time time,
  departure_name text, arrival_name text,
  nb_persons integer, has_luggage boolean,
  status text, driver_id uuid, driver_first_name text, driver_last_name text,
  driver_phone text, driver_comment text
)
language sql security definer set search_path = public, extensions as $$
  select
    r.id, r.ride_date, r.ride_time,
    coalesce(dl.name, r.departure_custom) as departure_name,
    coalesce(al.name, r.arrival_custom) as arrival_name,
    r.nb_persons, r.has_luggage, r.status,
    r.driver_id, d.first_name, d.last_name,
    case when r.status in ('proposed','confirmed') then d.phone else null end,
    r.driver_comment
  from ride_requests r
  left join locations dl on dl.id = r.departure_location_id
  left join locations al on al.id = r.arrival_location_id
  left join guests d on d.id = r.driver_id
  where r.requester_id = p_requester_id
  order by r.ride_date, r.ride_time;
$$;

-- ----------------------------------------------------------------------------
-- RPC : trajets en attente, visibles par les chauffeurs (pas les siens)
-- ----------------------------------------------------------------------------
create or replace function list_available_rides(p_driver_id uuid)
returns table(
  id uuid, ride_date date, ride_time time,
  departure_name text, arrival_name text,
  nb_persons integer, has_luggage boolean,
  requester_first_name text, requester_last_name text
)
language sql security definer set search_path = public, extensions as $$
  select
    r.id, r.ride_date, r.ride_time,
    coalesce(dl.name, r.departure_custom),
    coalesce(al.name, r.arrival_custom),
    r.nb_persons, r.has_luggage,
    g.first_name, g.last_name
  from ride_requests r
  left join locations dl on dl.id = r.departure_location_id
  left join locations al on al.id = r.arrival_location_id
  join guests g on g.id = r.requester_id
  where r.status = 'pending' and r.requester_id <> p_driver_id
  order by r.ride_date, r.ride_time;
$$;

-- ----------------------------------------------------------------------------
-- RPC : trajets pris en charge (proposés/confirmés) par un chauffeur
-- ----------------------------------------------------------------------------
create or replace function list_my_driven_rides(p_driver_id uuid)
returns table(
  id uuid, ride_date date, ride_time time,
  departure_name text, arrival_name text,
  nb_persons integer, has_luggage boolean,
  status text, driver_comment text,
  requester_first_name text, requester_last_name text, requester_phone text
)
language sql security definer set search_path = public, extensions as $$
  select
    r.id, r.ride_date, r.ride_time,
    coalesce(dl.name, r.departure_custom),
    coalesce(al.name, r.arrival_custom),
    r.nb_persons, r.has_luggage, r.status, r.driver_comment,
    g.first_name, g.last_name,
    case when r.status = 'confirmed' then g.phone else null end
  from ride_requests r
  left join locations dl on dl.id = r.departure_location_id
  left join locations al on al.id = r.arrival_location_id
  join guests g on g.id = r.requester_id
  where r.driver_id = p_driver_id and r.status in ('proposed','confirmed')
  order by r.ride_date, r.ride_time;
$$;

-- ----------------------------------------------------------------------------
-- RPC : un chauffeur propose de prendre en charge un trajet
-- ----------------------------------------------------------------------------
create or replace function propose_ride(p_driver_id uuid, p_ride_id uuid, p_comment text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set driver_id = p_driver_id, driver_comment = p_comment,
      status = 'proposed', updated_at = now()
  where id = p_ride_id and status = 'pending';

  if not found then
    raise exception 'ride_not_available';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : le chauffeur modifie son commentaire / conditions
-- ----------------------------------------------------------------------------
create or replace function update_driver_comment(p_driver_id uuid, p_ride_id uuid, p_comment text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set driver_comment = p_comment, updated_at = now()
  where id = p_ride_id and driver_id = p_driver_id and status in ('proposed','confirmed');

  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : le chauffeur annule sa prise en charge -> le trajet redevient 'pending'
-- ----------------------------------------------------------------------------
create or replace function cancel_driver_proposal(p_driver_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set driver_id = null, driver_comment = null, status = 'pending', updated_at = now()
  where id = p_ride_id and driver_id = p_driver_id and status in ('proposed','confirmed');

  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : l'invité demandeur confirme la prise en charge proposée par le chauffeur
-- ----------------------------------------------------------------------------
create or replace function confirm_ride(p_requester_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set status = 'confirmed', updated_at = now()
  where id = p_ride_id and requester_id = p_requester_id and status = 'proposed';

  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : l'invité demandeur refuse la proposition -> retour en 'pending'
-- ----------------------------------------------------------------------------
create or replace function reject_ride_proposal(p_requester_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set driver_id = null, driver_comment = null, status = 'pending', updated_at = now()
  where id = p_ride_id and requester_id = p_requester_id and status = 'proposed';

  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC : l'invité demandeur annule sa propre demande
-- ----------------------------------------------------------------------------
create or replace function cancel_ride_request(p_requester_id uuid, p_ride_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update ride_requests
  set status = 'cancelled', updated_at = now()
  where id = p_ride_id and requester_id = p_requester_id and status in ('pending','proposed','confirmed');

  if not found then
    raise exception 'ride_not_found';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- Données de base : quelques lieux préconfigurés (à adapter)
-- ----------------------------------------------------------------------------
insert into locations (name, sort_order) values
  ('Gare', 1),
  ('Aéroport', 2),
  ('Lieu de la cérémonie', 3),
  ('Lieu de la réception', 4),
  ('Hôtel des invités', 5)
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- Exemple pour ajouter des invités (à exécuter / adapter manuellement) :
-- insert into guests (first_name, last_name, email, phone, has_vehicle, vehicle_seats)
-- values ('Marie', 'Dupont', 'marie.dupont@example.com', '+33612345678', true, 4);
-- ----------------------------------------------------------------------------
