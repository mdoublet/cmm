-- Correctif : pgcrypto installé hors du search_path par défaut des fonctions.
-- A exécuter une fois dans le SQL Editor de Supabase si vous avez l'erreur
-- "function gen_salt(unknown) does not exist".

create extension if not exists pgcrypto with schema extensions;

alter function get_guest_status(text) set search_path = public, extensions;
alter function set_guest_code(text, text) set search_path = public, extensions;
alter function verify_guest_code(text, text) set search_path = public, extensions;
