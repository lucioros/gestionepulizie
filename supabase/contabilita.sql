-- =====================================================================
--  Gestione impresa pulizie · CONTABILITÀ GENERALE (conto economico)
--  Come usarlo: Supabase → SQL Editor → New query → incolla tutto → Run.
--  Va eseguito DOPO schema.sql e schema_v2.sql. Si può rilanciare.
--
--  Aggiunge:
--   - conti_economici: il piano dei conti di costo e ricavo (modificabile)
--   - scritture: costi e ricavi senza movimento di cassa (ammortamenti, competenze)
--   - la colonna conto_ec su movimenti di prima nota e fatture d'acquisto
--  e classifica i dati già presenti dove la causale o la categoria lo dicono.
-- =====================================================================
set client_min_messages = warning;

create table if not exists public.conti_economici (
  id            text primary key,
  nome          text not null,
  tipo          text not null check (tipo in ('ricavo', 'costo')),
  gruppo        text not null,
  ordine        integer,
  attivo        boolean not null default true,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

create table if not exists public.scritture (
  id            text primary key,
  data          date not null,
  conto_ec      text not null references public.conti_economici (id) on delete restrict,
  importo       numeric(14,2) not null,
  descrizione   text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create index if not exists scritture_data on public.scritture (data);

alter table public.movimenti add column if not exists conto_ec text references public.conti_economici (id) on delete set null;
alter table public.acquisti  add column if not exists conto_ec text references public.conti_economici (id) on delete set null;
create index if not exists movimenti_conto_ec on public.movimenti (conto_ec);
create index if not exists acquisti_conto_ec on public.acquisti (conto_ec);

-- piano dei conti predefinito (i nomi si possono cambiare dall'app)
insert into public.conti_economici (id, nome, tipo, gruppo, ordine) values
  ('r_servizi',      'Servizi di pulizia (fatture emesse)',     'ricavo', 'vendite',       10),
  ('r_altri',        'Altri ricavi e rimborsi',                 'ricavo', 'altri_ricavi',  20),
  ('r_contributi',   'Contributi e agevolazioni',               'ricavo', 'altri_ricavi',  21),
  ('r_interessi',    'Interessi attivi',                        'ricavo', 'fin_proventi',  30),
  ('c_prodotti',     'Prodotti di pulizia',                     'costo',  'materiali',    100),
  ('c_attrezzature', 'Attrezzature e piccoli macchinari',       'costo',  'materiali',    101),
  ('c_dpi',          'Divise e DPI',                            'costo',  'materiali',    102),
  ('c_carburante',   'Carburante e trasporti',                  'costo',  'servizi',      110),
  ('c_professionali','Consulenze e servizi professionali',      'costo',  'servizi',      111),
  ('c_manutenzioni', 'Manutenzioni',                            'costo',  'servizi',      112),
  ('c_assicurazioni','Assicurazioni',                           'costo',  'servizi',      113),
  ('c_subappalti',   'Subappalti e collaborazioni',             'costo',  'servizi',      114),
  ('c_utenze',       'Utenze e telefonia',                      'costo',  'servizi',      115),
  ('c_affitto',      'Affitti',                                 'costo',  'beni_terzi',   120),
  ('c_noleggi',      'Noleggi',                                 'costo',  'beni_terzi',   121),
  ('c_stipendi',     'Stipendi netti',                          'costo',  'personale',    130),
  ('c_contributi',   'Contributi INPS e INAIL',                 'costo',  'personale',    131),
  ('c_tfr',          'TFR e altri costi del personale',         'costo',  'personale',    132),
  ('c_ammortamenti', 'Ammortamenti',                            'costo',  'ammortamenti', 140),
  ('c_tasse',        'Tributi, bolli e tasse diverse',          'costo',  'oneri_diversi',150),
  ('c_altri',        'Altri costi',                             'costo',  'oneri_diversi',151),
  ('c_banca',        'Spese e interessi bancari',               'costo',  'fin_oneri',    160),
  ('c_imposte',      'Imposte sul reddito (IRES, IRAP, IRPEF)', 'costo',  'imposte',      170)
on conflict (id) do nothing;

-- categorie di costo già usate in fatture e fornitori → conti
do $$
declare r record; m jsonb := '{"Prodotti di pulizia":"c_prodotti","Attrezzature e macchinari":"c_attrezzature","Noleggi":"c_noleggi",
  "Carburante e trasporti":"c_carburante","Servizi professionali":"c_professionali","Affitto e utenze":"c_affitto","Divise e DPI":"c_dpi",
  "Assicurazioni":"c_assicurazioni","Manutenzioni":"c_manutenzioni","Altro":"c_altri"}';
begin
  -- categorie personalizzate: diventano conti di costo nel gruppo Servizi
  for r in select distinct trim(categoria) c from (select categoria from public.acquisti union all select categoria from public.fornitori) x
           where coalesce(trim(categoria), '') <> '' and not (m ? trim(categoria)) loop
    insert into public.conti_economici (id, nome, tipo, gruppo, ordine)
    values ('c_x_' || substr(md5(r.c), 1, 10), r.c, 'costo', 'servizi', 119) on conflict (id) do nothing;
  end loop;
  update public.acquisti a set conto_ec = coalesce(m ->> trim(a.categoria), 'c_x_' || substr(md5(trim(a.categoria)), 1, 10))
   where a.conto_ec is null and coalesce(trim(a.categoria), '') <> '';
  -- uscite ed entrate di prima nota con una causale che indica chiaramente la voce
  update public.movimenti set conto_ec = case causale
      when 'Stipendi' then 'c_stipendi' when 'Spese bancarie' then 'c_banca' when 'Carburante' then 'c_carburante'
      when 'Altre spese' then 'c_altri' when 'Altri ricavi' then 'r_altri' when 'Rimborso ricevuto' then 'r_altri' end
   where conto_ec is null and tipo in ('entrata', 'uscita')
     and causale in ('Stipendi', 'Spese bancarie', 'Carburante', 'Altre spese', 'Altri ricavi', 'Rimborso ricevuto');
end $$;

-- data di aggiornamento automatica
do $$
declare t text;
begin
  foreach t in array array['conti_economici','scritture'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_aggiornato', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.tocca_aggiornato()', t || '_aggiornato', t);
  end loop;
end $$;

-- registro degli archivi (per salva_lotto) e permessi: solo il titolare
insert into public.archivi (tab) values ('conti_economici'), ('scritture') on conflict (tab) do nothing;
do $$
declare t text;
begin
  foreach t in array array['conti_economici','scritture'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists titolare on public.%I', t);
    execute format('create policy titolare on public.%I for all to authenticated using (is_titolare()) with check (is_titolare())', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['conti_economici','scritture'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- Fatto. Verifica: numero di conti e registrazioni già classificate.
select (select count(*) from public.conti_economici) as conti,
       (select count(*) from public.acquisti where conto_ec is not null) as acquisti_classificati,
       (select count(*) from public.movimenti where conto_ec is not null) as movimenti_classificati;
