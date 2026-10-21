-- =====================================================================
--  Registro Pulizie · schema del database Supabase
--  Come usarlo: Supabase → SQL Editor → New query → incolla tutto → Run.
--  Si può rilanciare senza perdere dati: crea solo quello che manca
--  e aggiorna funzioni e permessi.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Impostazioni: chi è il titolare
--    L'account che si registra con questa email vede e gestisce tutto.
--    Se usi un'altra email per il gestionale, cambiala qui sotto.
-- ---------------------------------------------------------------------
create table if not exists public.impostazioni (
  id             int primary key default 1 check (id = 1),
  email_titolare text not null,
  gps_attivo     boolean not null default false
);
insert into public.impostazioni (id, email_titolare)
values (1, 'luciorosalba@gmail.com')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Archivio del gestionale: un documento JSON per ogni record
--    (clienti, sedi, operatori, fatture, movimenti, ...).
--    col = tipo di record, id = codice del record.
--    La collezione "agenda" contiene i turni pubblicati per ogni
--    dipendente (id = codice dell'operatore): è l'unica che i
--    dipendenti possono leggere, e solo la propria.
-- ---------------------------------------------------------------------
create table if not exists public.docs (
  col        text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (col, id)
);
create index if not exists docs_operatori_email
  on public.docs (lower(data->>'emailApp')) where col = 'operatori';

create or replace function public.tocca_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists docs_updated_at on public.docs;
create trigger docs_updated_at before update on public.docs
  for each row execute function public.tocca_updated_at();

-- ---------------------------------------------------------------------
-- 3. Timbrature dei dipendenti (inizio e fine di ogni turno)
--    L'ora è sempre quella del server: il telefono non può falsificarla.
-- ---------------------------------------------------------------------
create table if not exists public.timbrature (
  id           uuid primary key default gen_random_uuid(),
  operatore_id text not null,
  turno_id     text not null,
  data         date not null,
  tipo         text not null check (tipo in ('inizio', 'fine')),
  ts           timestamptz not null default now(),
  lat          double precision,
  lng          double precision,
  precisione   double precision,
  nota         text,
  utente       uuid default auth.uid(),
  corretta     boolean not null default false
);
create unique index if not exists timbrature_una_per_tipo
  on public.timbrature (operatore_id, turno_id, tipo);
create index if not exists timbrature_data on public.timbrature (data);

-- ---------------------------------------------------------------------
-- 4. Chi sta usando l'app
-- ---------------------------------------------------------------------
create or replace function public.is_titolare() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') = (select lower(email_titolare) from impostazioni where id = 1),
    false)
$$;

-- codice dell'operatore collegato all'email di chi è entrato
-- (campo "Email per l'app dipendenti" nella scheda operatore)
create or replace function public.mio_operatore() returns text
language sql stable security definer set search_path = public as $$
  select id from docs
  where col = 'operatori'
    and lower(data->>'emailApp') = lower(auth.jwt() ->> 'email')
    and coalesce(data->>'attivo', 'true') <> 'false'
  limit 1
$$;

-- impostazioni lette dall'app dipendenti
create or replace function public.gps_attivo() returns boolean
language sql stable security definer set search_path = public as $$
  select gps_attivo from impostazioni where id = 1
$$;

-- ---------------------------------------------------------------------
-- 5. Controlli sulle timbrature dei dipendenti
-- ---------------------------------------------------------------------
create or replace function public.controlla_timbratura() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  op text;
begin
  if is_titolare() then
    new.corretta := (tg_op = 'UPDATE') or new.corretta;
    return new;
  end if;
  op := mio_operatore();
  if op is null then
    raise exception 'Il tuo account non è collegato a nessun dipendente attivo';
  end if;
  new.operatore_id := op;
  new.ts           := now();
  new.utente       := auth.uid();
  new.corretta     := false;
  if new.data < (now() at time zone 'Europe/Rome')::date - 1
     or new.data > (now() at time zone 'Europe/Rome')::date + 1 then
    raise exception 'Si può timbrare solo un turno di oggi';
  end if;
  if not exists (
    select 1
    from docs d,
         jsonb_array_elements(coalesce(d.data->'giorni', '[]'::jsonb)) g,
         jsonb_array_elements(coalesce(g->'turni', '[]'::jsonb)) t
    where d.col = 'agenda' and d.id = op and t->>'id' = new.turno_id
  ) then
    raise exception 'Questo turno non è nella tua agenda';
  end if;
  if new.tipo = 'fine' and not exists (
    select 1 from timbrature
    where operatore_id = op and turno_id = new.turno_id and tipo = 'inizio'
  ) then
    raise exception 'Segna prima l''inizio del lavoro';
  end if;
  return new;
end $$;
drop trigger if exists timbrature_controllo on public.timbrature;
create trigger timbrature_controllo before insert or update on public.timbrature
  for each row execute function public.controlla_timbratura();

-- ---------------------------------------------------------------------
-- 6. Permessi (Row Level Security)
--    Titolare: legge e scrive tutto.
--    Dipendente: legge solo la propria agenda e le proprie timbrature,
--                può solo aggiungere timbrature proprie.
--    Senza login: nessun accesso.
-- ---------------------------------------------------------------------
alter table public.impostazioni enable row level security;
alter table public.docs         enable row level security;
alter table public.timbrature   enable row level security;

drop policy if exists imp_titolare on public.impostazioni;
create policy imp_titolare on public.impostazioni for all to authenticated
  using (is_titolare()) with check (is_titolare());

drop policy if exists docs_titolare on public.docs;
create policy docs_titolare on public.docs for all to authenticated
  using (is_titolare()) with check (is_titolare());

drop policy if exists docs_agenda_dipendente on public.docs;
create policy docs_agenda_dipendente on public.docs for select to authenticated
  using (col = 'agenda' and id = mio_operatore());

drop policy if exists timb_titolare on public.timbrature;
create policy timb_titolare on public.timbrature for all to authenticated
  using (is_titolare()) with check (is_titolare());

drop policy if exists timb_dip_lettura on public.timbrature;
create policy timb_dip_lettura on public.timbrature for select to authenticated
  using (operatore_id = mio_operatore());

drop policy if exists timb_dip_inserimento on public.timbrature;
create policy timb_dip_inserimento on public.timbrature for insert to authenticated
  with check (operatore_id = mio_operatore());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.docs, public.timbrature, public.impostazioni to authenticated;
revoke all on public.docs, public.timbrature, public.impostazioni from anon;
grant execute on function public.is_titolare(), public.mio_operatore(), public.gps_attivo() to authenticated;
-- nessuna funzione si può chiamare senza login
alter function public.tocca_updated_at() set search_path = public;
revoke execute on function public.is_titolare(), public.mio_operatore(), public.gps_attivo(),
  public.controlla_timbratura() from public, anon;
revoke execute on function public.controlla_timbratura() from authenticated;

-- ---------------------------------------------------------------------
-- 7. Aggiornamenti in tempo reale (gestionale aperto su più dispositivi,
--    timbrature che arrivano mentre guardi la giornata)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'docs') then
      alter publication supabase_realtime add table public.docs;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'timbrature') then
      alter publication supabase_realtime add table public.timbrature;
    end if;
  end if;
end $$;

-- Fatto. Verifica: la query qui sotto deve restituire la tua email.
select email_titolare from public.impostazioni;
