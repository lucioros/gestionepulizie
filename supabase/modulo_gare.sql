-- =====================================================================
--  Gestione impresa pulizie · modulo GARE D'APPALTO
--  Come usarlo: Supabase → SQL Editor → New query → incolla tutto → Run.
--  Va eseguito DOPO schema.sql e schema_v2.sql. Si può rilanciare.
--
--  Il modulo si attiva e si disattiva con l'elenco "moduli" (oggi nella
--  tabella impostazioni). Con il modulo spento le sue tabelle non si
--  leggono e non si scrivono: lo impone il database, non solo l'app.
-- =====================================================================
set client_min_messages = warning;

-- alla prima installazione il modulo parte attivo
do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'gare') then
    update public.impostazioni set moduli = array_append(moduli, 'gare') where not ('gare' = any(moduli));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Tabelle del costo del lavoro (CCNL, ambito territoriale, livelli)
-- ---------------------------------------------------------------------
create table if not exists public.costi_lavoro (
  id            text primary key,
  nome          text not null,
  ccnl          text,
  ambito        text,
  decorrenza    date,
  fonte         text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create table if not exists public.costi_lavoro_livelli (
  tabella_id   text not null references public.costi_lavoro (id) on delete cascade,
  pos          integer not null,
  livello      text not null,
  descrizione  text,
  costo_orario numeric(10,2) not null,
  primary key (tabella_id, pos)
);

-- ---------------------------------------------------------------------
-- 2. Documenti dell'impresa con scadenza (DURC, visura, certificazioni...)
-- ---------------------------------------------------------------------
create table if not exists public.documenti_impresa (
  id            text primary key,
  tipo          text not null,
  descrizione   text,
  numero        text,
  ente          text,
  rilascio      date,
  scadenza      date,
  file          text,
  nome_file     text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Gare e richieste di offerta
-- ---------------------------------------------------------------------
create table if not exists public.gare (
  id                   text primary key,
  oggetto              text not null,
  tipo                 text not null default 'pubblica' check (tipo in ('pubblica', 'privata')),
  ente                 text,
  ente_cf              text,
  ente_codice          text,
  ente_pec             text,
  cig                  text,
  cup                  text,
  piattaforma          text,
  link                 text,
  procedura            text,
  criterio             text check (criterio is null or criterio in ('oepv', 'prezzo')),
  punti_tecnici        numeric(6,2),
  punti_economici      numeric(6,2),
  formula              text,
  coeff_x              numeric(4,2),
  importo_base         numeric(14,2),
  manodopera_sa        numeric(14,2),
  oneri_sicurezza      numeric(14,2),
  durata_mesi          integer,
  rinnovo_mesi         integer,
  data_pubblicazione   date,
  sopralluogo          date,
  sopralluogo_obbl     boolean,
  scad_chiarimenti     date,
  scad_offerta         date,
  ora_offerta          text,
  apertura_buste       date,
  cam                  boolean,
  clausola_sociale     boolean,
  requisiti            text[],
  stato                text not null default 'individuata',
  motivo               text,
  note                 text,
  cliente_id           text references public.clienti (id) on delete set null,
  -- calcolo dell'offerta
  costi_lavoro_id      text references public.costi_lavoro (id) on delete set null,
  livello_base         text,
  materiali_pct        numeric(6,2),
  attrezzature_anno    numeric(14,2),
  sicurezza_anno       numeric(14,2),
  generali_pct         numeric(6,2),
  utile_pct            numeric(6,2),
  ribasso_max_atteso   numeric(6,3),
  ribasso_medio_atteso numeric(6,3),
  tecnico_stimato      numeric(6,2),
  -- offerta presentata ed esito
  importo_offerto      numeric(14,2),
  ribasso_offerto      numeric(6,3),
  data_esito           date,
  aggiudicatario       text,
  ribasso_aggiudicazione numeric(6,3),
  punteggio_tecnico    numeric(6,2),
  punteggio_economico  numeric(6,2),
  posizione            integer,
  -- garanzie
  gar_prov_importo     numeric(14,2),
  gar_prov_scadenza    date,
  gar_prov_emittente   text,
  gar_prov_svincolata  boolean,
  cauz_def_importo     numeric(14,2),
  cauz_def_scadenza    date,
  cauz_def_emittente   text,
  cauz_def_svincolata  boolean,
  -- contratto
  data_stipula         date,
  data_inizio          date,
  data_fine            date,
  revisione_prezzi     text,
  penali               text,
  esempio              boolean,
  extra                jsonb not null default '{}'::jsonb,
  creato_il            timestamptz not null default now(),
  aggiornato_il        timestamptz not null default now()
);
create index if not exists gare_stato on public.gare (stato, scad_offerta);
create index if not exists gare_cliente on public.gare (cliente_id);

-- calcolo delle ore: una riga per ambiente (per lotto)
create table if not exists public.gare_voci (
  gara_id   text not null references public.gare (id) on delete cascade,
  pos       integer not null,
  lotto     text,
  descr     text,
  mq        numeric(12,2),
  passaggi  numeric(10,2),
  resa      numeric(10,2),
  ore_extra numeric(10,2),
  livello   text,
  primary key (gara_id, pos)
);
-- personale da assorbire per la clausola sociale
create table if not exists public.gare_personale (
  gara_id  text not null references public.gare (id) on delete cascade,
  pos      integer not null,
  nome     text,
  livello  text,
  ore_sett numeric(6,2),
  primary key (gara_id, pos)
);
-- documenti da preparare per la gara
create table if not exists public.gare_documenti (
  gara_id   text not null references public.gare (id) on delete cascade,
  pos       integer not null,
  nome      text not null,
  stato     text not null default 'da fare',
  file      text,
  nome_file text,
  note      text,
  primary key (gara_id, pos)
);
-- esito: concorrenti, ribassi e punteggi
create table if not exists public.gare_concorrenti (
  gara_id        text not null references public.gare (id) on delete cascade,
  pos            integer not null,
  nome           text not null,
  ribasso        numeric(6,3),
  punti_tecnici  numeric(6,2),
  punti_totali   numeric(6,2),
  aggiudicatario boolean,
  primary key (gara_id, pos)
);

-- data di aggiornamento automatica
do $$
declare t text;
begin
  foreach t in array array['costi_lavoro','documenti_impresa','gare'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_aggiornato', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.tocca_aggiornato()', t || '_aggiornato', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4. Registro degli archivi del modulo (per la funzione salva_lotto)
-- ---------------------------------------------------------------------
insert into public.archivi (tab, modulo) values
  ('costi_lavoro', 'gare'), ('documenti_impresa', 'gare'), ('gare', 'gare')
on conflict (tab) do update set modulo = excluded.modulo;
insert into public.archivi_figli (padre, figlio, fk) values
  ('costi_lavoro', 'costi_lavoro_livelli', 'tabella_id'),
  ('gare', 'gare_voci', 'gara_id'),
  ('gare', 'gare_personale', 'gara_id'),
  ('gare', 'gare_documenti', 'gara_id'),
  ('gare', 'gare_concorrenti', 'gara_id')
on conflict (padre, figlio) do nothing;

-- ---------------------------------------------------------------------
-- 5. Permessi: solo il titolare e solo con il modulo attivo
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['costi_lavoro','costi_lavoro_livelli','documenti_impresa','gare','gare_voci',
    'gare_personale','gare_documenti','gare_concorrenti'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists titolare on public.%I', t);
    execute format('create policy titolare on public.%I for all to authenticated using (is_titolare() and modulo_attivo(''gare'')) with check (is_titolare() and modulo_attivo(''gare''))', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. Allegati (bandi, capitolati, documenti firmati): spazio file privato
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage')
     and exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('allegati', 'allegati', false, 20971520)
    on conflict (id) do nothing;
    drop policy if exists allegati_titolare on storage.objects;
    create policy allegati_titolare on storage.objects for all to authenticated
      using (bucket_id = 'allegati' and public.is_titolare())
      with check (bucket_id = 'allegati' and public.is_titolare());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. Aggiornamenti in tempo reale
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['costi_lavoro','documenti_impresa','gare'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- Fatto. Verifica: deve comparire "gare" tra i moduli attivi.
select moduli from public.impostazioni;
