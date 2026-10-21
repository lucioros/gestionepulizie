-- =====================================================================
--  Registro Pulizie · schema v2: tabelle relazionali
--  Come usarlo: Supabase → SQL Editor → New query → incolla tutto → Run.
--
--  - Crea una tabella per ogni archivio (clienti, sedi, fatture, ...)
--    con i collegamenti tra loro (chiavi esterne).
--  - Non cancella e non modifica la vecchia tabella "docs": i dati
--    restano lì come copia finché non li trasferisci dal gestionale
--    (Impostazioni → Trasferisci i dati nelle nuove tabelle).
--  - Si può rilanciare senza perdere dati: crea solo quello che manca
--    e aggiorna funzioni e permessi.
--  - Richiede che schema.sql (v1) sia già stato eseguito: usa le stesse
--    tabelle "impostazioni" e "timbrature".
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Funzioni di servizio
-- ---------------------------------------------------------------------
set client_min_messages = warning;

create or replace function public.tocca_aggiornato() returns trigger
language plpgsql as $$ begin new.aggiornato_il := now(); return new; end $$;

-- ---------------------------------------------------------------------
-- 1. Anagrafiche e tabelle di base
-- ---------------------------------------------------------------------
create table if not exists public.amministratori (
  id            text primary key,
  nome          text not null,
  referente     text,
  cf            text,
  tel           text,
  email         text,
  pec           text,
  indirizzo     text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

create table if not exists public.conti (
  id             text primary key,
  nome           text not null,
  iban           text,
  saldo_iniziale numeric(14,2),
  data_saldo     date,
  esempio        boolean,
  extra          jsonb not null default '{}'::jsonb,
  creato_il      timestamptz not null default now(),
  aggiornato_il  timestamptz not null default now()
);
-- i due conti predefiniti del gestionale
insert into public.conti (id, nome, saldo_iniziale) values
  ('cassa', 'Cassa contanti', 0), ('banca', 'Banca', 0)
on conflict (id) do nothing;

create table if not exists public.pagamenti (
  id              text primary key,
  descrizione     text not null,
  strumento       text,
  rate            text,
  base            text check (base in ('DF', 'FM')),
  giorno_fisso    integer check (giorno_fisso between 1 and 31),
  iva_prima_rata  boolean,
  mesi_esclusi    integer[],
  slittamento     integer,
  conto           text references public.conti (id) on update cascade on delete restrict,
  note            text,
  esempio         boolean,
  extra           jsonb not null default '{}'::jsonb,
  creato_il       timestamptz not null default now(),
  aggiornato_il   timestamptz not null default now()
);

create table if not exists public.clienti (
  id               text primary key,
  nome             text not null,
  piva             text,
  cf               text,
  referente        text,
  amministratore_id text references public.amministratori (id) on delete restrict,
  tel              text,
  email            text,
  pec              text,
  indirizzo        text,
  cap              text,
  comune           text,
  provincia        text,
  nazione          text,
  sdi              text,
  pagamento        text references public.pagamenti (id) on delete restrict,
  cod_iva          text,
  ritenuta         boolean,
  note             text,
  esempio          boolean,
  extra            jsonb not null default '{}'::jsonb,
  creato_il        timestamptz not null default now(),
  aggiornato_il    timestamptz not null default now()
);
create index if not exists clienti_amministratore on public.clienti (amministratore_id);

-- righe abituali in fattura di ogni cliente
create table if not exists public.clienti_righe (
  cliente_id text not null references public.clienti (id) on delete cascade,
  pos        integer not null,
  descr      text,
  qta        numeric(14,4),
  prezzo     numeric(14,4),
  cod        text,
  primary key (cliente_id, pos)
);

create table if not exists public.fornitori (
  id            text primary key,
  nome          text not null,
  piva          text,
  cf            text,
  categoria     text,
  tel           text,
  email         text,
  pec           text,
  indirizzo     text,
  cap           text,
  comune        text,
  provincia     text,
  iban          text,
  pagamento     text references public.pagamenti (id) on delete restrict,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

create table if not exists public.operatori (
  id               text primary key,
  nome             text not null,
  email_app        text,
  mansione         text,
  tel              text,
  costo_orario     numeric(10,2),
  ore_settimanali  numeric(6,2),
  attivo           boolean,
  note             text,
  esempio          boolean,
  extra            jsonb not null default '{}'::jsonb,
  creato_il        timestamptz not null default now(),
  aggiornato_il    timestamptz not null default now()
);
create unique index if not exists operatori_email_app
  on public.operatori (lower(email_app)) where coalesce(email_app, '') <> '';

-- elenchi ampliabili (tipi di immobile, categorie, causali, tipi di assenza, ...)
create table if not exists public.elenchi (
  id            text primary key,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create table if not exists public.elenchi_voci (
  elenco_id text not null references public.elenchi (id) on delete cascade,
  pos       integer not null,
  valore    text not null,
  primary key (elenco_id, pos)
);
-- codici IVA aggiunti dall'utente (quelli standard sono nell'app)
create table if not exists public.codici_iva (
  elenco_id   text not null default 'codiciIva' references public.elenchi (id) on delete cascade,
  pos         integer not null,
  id          text not null unique,
  descrizione text not null,
  trattamento text not null check (trattamento in ('norm', 'split', 'rc', 'ex', 'excl')),
  aliquota    numeric(5,2),
  natura      text,
  norma       text,
  primary key (elenco_id, pos)
);

-- dati della propria impresa per la fattura elettronica (una sola riga)
create table if not exists public.azienda (
  id               text primary key default 'azienda' check (id = 'azienda'),
  denominazione    text,
  piva             text,
  cf               text,
  regime_fiscale   text,
  indirizzo        text,
  cap              text,
  comune           text,
  provincia        text,
  tel              text,
  email            text,
  pec              text,
  iban             text,
  rea_ufficio      text,
  rea_numero       text,
  capitale_sociale numeric(14,2),
  socio_unico      text,
  tipo_ritenuta    text,
  causale_ritenuta text,
  fe_dal           date,
  progressivo      integer,
  extra            jsonb not null default '{}'::jsonb,
  creato_il        timestamptz not null default now(),
  aggiornato_il    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Operatività: sedi, turni, assenze, qualità, preventivi
-- ---------------------------------------------------------------------
create table if not exists public.sedi (
  id            text primary key,
  cliente_id    text not null references public.clienti (id) on delete restrict,
  nome          text not null,
  indirizzo     text,
  tipo          text,
  mq            numeric(10,2),
  giorni        integer[],
  ora           text check (ora is null or ora = '' or ora ~ '^\d{1,2}:\d{2}$'),
  durata        numeric(6,2),
  canone        numeric(14,2),
  attiva        boolean,
  accesso       text,
  attivita      text[],
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create index if not exists sedi_cliente on public.sedi (cliente_id);

-- squadra assegnata a ogni sede
create table if not exists public.sedi_operatori (
  sede_id      text not null references public.sedi (id) on delete cascade,
  pos          integer not null,
  operatore_id text not null references public.operatori (id) on delete cascade,
  primary key (sede_id, pos),
  unique (sede_id, operatore_id)
);
create index if not exists sedi_operatori_op on public.sedi_operatori (operatore_id);

-- esito dei turni ricorrenti (svolto / saltato); id = sede_data
create table if not exists public.registro (
  id            text primary key,
  sede_id       text not null references public.sedi (id) on delete cascade,
  data          date not null,
  stato         text not null,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create index if not exists registro_sede_data on public.registro (sede_id, data);

-- modifiche a un singolo turno ricorrente; id = sede_data originale
create table if not exists public.variazioni (
  id            text primary key,
  sede_id       text not null references public.sedi (id) on delete cascade,
  orig_data     date not null,
  data          date not null,
  ora           text,
  durata        numeric(6,2),
  nota          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create table if not exists public.variazioni_operatori (
  variazione_id text not null references public.variazioni (id) on delete cascade,
  pos           integer not null,
  operatore_id  text not null references public.operatori (id) on delete cascade,
  primary key (variazione_id, pos)
);

create table if not exists public.straordinari (
  id            text primary key,
  sede_id       text not null references public.sedi (id) on delete restrict,
  descrizione   text,
  data          date not null,
  ora           text,
  durata        numeric(6,2),
  importo       numeric(14,2),
  stato         text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create table if not exists public.straordinari_operatori (
  straordinario_id text not null references public.straordinari (id) on delete cascade,
  pos              integer not null,
  operatore_id     text not null references public.operatori (id) on delete cascade,
  primary key (straordinario_id, pos)
);

create table if not exists public.assenze (
  id            text primary key,
  operatore_id  text not null references public.operatori (id) on delete cascade,
  tipo          text,
  dal           date not null,
  al            date,
  dalle         text,
  alle          text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now(),
  check (al is null or al >= dal)
);
create index if not exists assenze_operatore on public.assenze (operatore_id, dal);

create table if not exists public.ispezioni (
  id            text primary key,
  sede_id       text not null references public.sedi (id) on delete restrict,
  data          date not null,
  ispettore     text,
  note          text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create table if not exists public.ispezioni_voti (
  ispezione_id text not null references public.ispezioni (id) on delete cascade,
  pos          integer not null,
  area         text not null,
  voto         integer check (voto between 1 and 5),
  primary key (ispezione_id, pos)
);

create table if not exists public.preventivi (
  id             text primary key,
  numero         text,
  data           date,
  cliente_id     text references public.clienti (id) on delete restrict,
  cliente        text,
  stato          text,
  descrizione    text,
  tipo           text,
  mq             numeric(10,2),
  giorni         numeric(4,1),
  produttivita   numeric(10,2),
  costo_orario   numeric(10,2),
  materiali      numeric(6,2),
  generali       numeric(6,2),
  margine        numeric(6,2),
  canone_offerto numeric(14,2),
  note           text,
  esempio        boolean,
  extra          jsonb not null default '{}'::jsonb,
  creato_il      timestamptz not null default now(),
  aggiornato_il  timestamptz not null default now()
);
create table if not exists public.preventivi_righe (
  preventivo_id text not null references public.preventivi (id) on delete cascade,
  pos           integer not null,
  descr         text,
  qta           numeric(14,4),
  prezzo        numeric(14,4),
  cod           text,
  primary key (preventivo_id, pos)
);

-- ---------------------------------------------------------------------
-- 3. Contabilità
-- ---------------------------------------------------------------------
create table if not exists public.fatture (
  id              text primary key,
  tipo            text not null default 'fattura' check (tipo in ('fattura', 'nc')),
  numero          text not null,
  cliente_id      text not null references public.clienti (id) on delete restrict,
  cliente_nome    text,
  data            date not null,
  mese            text,
  pagamento       text references public.pagamenti (id) on delete restrict,
  ritenuta        boolean,
  scadenza        date,
  rif_doc         text,
  rif_ordine      text,
  cig             text,
  cup             text,
  note            text,
  auto            boolean,
  stato           text,
  sdi_stato       text,
  sdi_progressivo text,
  sdi_file        text,
  sdi_generato    date,
  sdi_inviata     date,
  sdi_consegna    date,
  sdi_scarto      date,
  esempio         boolean,
  extra           jsonb not null default '{}'::jsonb,
  creato_il       timestamptz not null default now(),
  aggiornato_il   timestamptz not null default now(),
  unique (tipo, numero)
);
create index if not exists fatture_cliente on public.fatture (cliente_id, data);

create table if not exists public.fatture_righe (
  fattura_id text not null references public.fatture (id) on delete cascade,
  pos        integer not null,
  descr      text,
  qta        numeric(14,4),
  prezzo     numeric(14,4),
  cod        text,
  primary key (fattura_id, pos)
);
create table if not exists public.fatture_scadenze (
  fattura_id text not null references public.fatture (id) on delete cascade,
  pos        integer not null,
  data       date not null,
  importo    numeric(14,2) not null,
  primary key (fattura_id, pos)
);
-- preventivi da cui è nata la fattura
create table if not exists public.fatture_preventivi (
  fattura_id    text not null references public.fatture (id) on delete cascade,
  pos           integer not null,
  preventivo_id text not null references public.preventivi (id) on delete cascade,
  primary key (fattura_id, pos)
);
-- storico degli esiti del Sistema di Interscambio
create table if not exists public.fatture_sdi_storia (
  fattura_id text not null references public.fatture (id) on delete cascade,
  pos        integer not null,
  data       date,
  evento     text,
  primary key (fattura_id, pos)
);

create table if not exists public.acquisti (
  id            text primary key,
  fornitore_id  text not null references public.fornitori (id) on delete restrict,
  numero        text not null,
  data          date not null,
  data_reg      date,
  protocollo    text,
  categoria     text,
  pagamento     text references public.pagamenti (id) on delete restrict,
  ritenuta_pct  numeric(5,2),
  scadenza      date,
  note          text,
  file_xml      text,
  tipo_doc      text,
  stato         text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
create index if not exists acquisti_fornitore on public.acquisti (fornitore_id, data);
create table if not exists public.acquisti_righe (
  acquisto_id text not null references public.acquisti (id) on delete cascade,
  pos         integer not null,
  descr       text,
  qta         numeric(14,4),
  prezzo      numeric(14,4),
  cod         text,
  primary key (acquisto_id, pos)
);
create table if not exists public.acquisti_scadenze (
  acquisto_id text not null references public.acquisti (id) on delete cascade,
  pos         integer not null,
  data        date not null,
  importo     numeric(14,2) not null,
  primary key (acquisto_id, pos)
);

-- prima nota: entrate, uscite e giroconti
create table if not exists public.movimenti (
  id            text primary key,
  data          date not null,
  tipo          text not null check (tipo in ('entrata', 'uscita', 'giroconto')),
  conto         text not null references public.conti (id) on delete restrict,
  conto_dest    text references public.conti (id) on delete restrict,
  causale       text,
  importo       numeric(14,2) not null,
  cliente_id    text references public.clienti (id) on delete restrict,
  fornitore_id  text references public.fornitori (id) on delete restrict,
  descrizione   text,
  esempio       boolean,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now(),
  check (cliente_id is null or fornitore_id is null),
  check (tipo <> 'giroconto' or conto_dest is not null)
);
create index if not exists movimenti_data on public.movimenti (data);
create index if not exists movimenti_cliente on public.movimenti (cliente_id);
create index if not exists movimenti_fornitore on public.movimenti (fornitore_id);

-- abbinamenti: quale incasso, pagamento o nota di credito salda quale
-- fattura (e quale rata). Una riga per ogni importo abbinato.
create table if not exists public.abbinamenti (
  id           bigint generated by default as identity primary key,
  movimento_id text references public.movimenti (id) on delete cascade,
  nota_id      text references public.fatture (id) on delete cascade,
  pos          integer not null,
  fattura_id   text references public.fatture (id) on delete cascade,
  acquisto_id  text references public.acquisti (id) on delete cascade,
  rata         integer,
  importo      numeric(14,2) not null,
  check (num_nonnulls(movimento_id, nota_id) = 1),
  check (num_nonnulls(fattura_id, acquisto_id) = 1)
);
create index if not exists abbinamenti_movimento on public.abbinamenti (movimento_id);
create index if not exists abbinamenti_nota on public.abbinamenti (nota_id);
create index if not exists abbinamenti_fattura on public.abbinamenti (fattura_id);
create index if not exists abbinamenti_acquisto on public.abbinamenti (acquisto_id);

-- certificazioni uniche ricevute dai condomini; id = cliente_anno
create table if not exists public.cu (
  id            text primary key,
  cliente_id    text not null references public.clienti (id) on delete cascade,
  anno          integer not null,
  ricevuta      boolean,
  data          date,
  extra         jsonb not null default '{}'::jsonb,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now(),
  unique (cliente_id, anno)
);

-- ---------------------------------------------------------------------
-- 4. Agenda pubblicata per l'app dipendenti (calcolata dal gestionale)
-- ---------------------------------------------------------------------
create table if not exists public.agenda (
  operatore_id  text primary key references public.operatori (id) on delete cascade,
  data          jsonb not null,
  aggiornato_il timestamptz not null default now()
);

-- data di aggiornamento automatica
do $$
declare t text;
begin
  foreach t in array array['amministratori','conti','pagamenti','clienti','fornitori','operatori','elenchi','azienda',
    'sedi','registro','variazioni','straordinari','assenze','ispezioni','preventivi','fatture','acquisti','movimenti','cu','agenda']
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_aggiornato', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.tocca_aggiornato()', t || '_aggiornato', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. Chi sta usando l'app (ora legge le nuove tabelle)
-- ---------------------------------------------------------------------
create or replace function public.mio_operatore() returns text
language sql stable security definer set search_path = public as $$
  select id from operatori
  where lower(email_app) = lower(auth.jwt() ->> 'email')
    and coalesce(attivo, true)
  limit 1
$$;

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
    from agenda a,
         jsonb_array_elements(coalesce(a.data->'giorni', '[]'::jsonb)) g,
         jsonb_array_elements(coalesce(g->'turni', '[]'::jsonb)) t
    where a.operatore_id = op and t->>'id' = new.turno_id
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

-- ---------------------------------------------------------------------
-- 6. Salvataggio dal gestionale
--    salva_lotto riceve un elenco di operazioni e le esegue tutte in
--    un'unica transazione: o riescono tutte o nessuna.
--    Ogni operazione è
--      {"tab": "fatture", "riga": {...}, "figli": {"fatture_righe": [...], ...}}
--    oppure {"tab": "fatture", "elimina": "<id>"}.
--    Gira con i permessi di chi la chiama: valgono le regole del punto 7.
-- ---------------------------------------------------------------------
create or replace function public.figlio_fk(p_padre text, p_figlio text) returns text
language sql immutable as $$
  select fk from (values
    ('clienti','clienti_righe','cliente_id'),
    ('elenchi','elenchi_voci','elenco_id'),
    ('elenchi','codici_iva','elenco_id'),
    ('sedi','sedi_operatori','sede_id'),
    ('variazioni','variazioni_operatori','variazione_id'),
    ('straordinari','straordinari_operatori','straordinario_id'),
    ('ispezioni','ispezioni_voti','ispezione_id'),
    ('preventivi','preventivi_righe','preventivo_id'),
    ('fatture','fatture_righe','fattura_id'),
    ('fatture','fatture_scadenze','fattura_id'),
    ('fatture','fatture_preventivi','fattura_id'),
    ('fatture','fatture_sdi_storia','fattura_id'),
    ('fatture','abbinamenti','nota_id'),
    ('acquisti','acquisti_righe','acquisto_id'),
    ('acquisti','acquisti_scadenze','acquisto_id'),
    ('movimenti','abbinamenti','movimento_id')
  ) v(padre, figlio, fk) where padre = p_padre and figlio = p_figlio
$$;

create or replace function public.salva_lotto(p_ops jsonb) returns integer
language plpgsql security invoker set search_path = public as $$
declare
  op jsonb; t text; rid text; riga jsonb; k text; fk text; righe jsonb;
  cols text; upd text; bad text; n integer := 0;
  padri constant text[] := array['amministratori','conti','pagamenti','clienti','fornitori','operatori','elenchi','azienda',
    'sedi','registro','variazioni','straordinari','assenze','ispezioni','preventivi','fatture','acquisti','movimenti','cu'];
begin
  if not is_titolare() then
    raise exception 'Solo il titolare può modificare i dati' using errcode = '42501';
  end if;
  for op in select value from jsonb_array_elements(p_ops) loop
    t := op->>'tab';
    if t is null or not (t = any (padri)) then
      raise exception 'Archivio non previsto: %', t using errcode = '22023';
    end if;

    if op ? 'elimina' then
      execute format('delete from public.%I where id = $1', t) using op->>'elimina';
      n := n + 1;
      continue;
    end if;

    riga := op->'riga';
    rid := riga->>'id';
    if rid is null or rid = '' then
      raise exception 'Record senza codice in %', t using errcode = '22023';
    end if;
    -- ogni campo deve essere una colonna della tabella
    select string_agg(key, ', ') into bad from jsonb_object_keys(riga) key
    where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = t and c.column_name = key);
    if bad is not null then
      raise exception 'Campi sconosciuti in %: %', t, bad using errcode = '22023';
    end if;
    select string_agg(quote_ident(key), ', '), string_agg('excluded.' || quote_ident(key), ', ')
      into cols, upd from jsonb_object_keys(riga) key;
    execute format('insert into public.%1$I as x (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1) '
                   'on conflict (id) do update set (%2$s) = row(%3$s)', t, cols, upd)
      using riga;

    -- tabelle figlie: si sostituiscono tutte le righe del record
    for k, righe in select key, value from jsonb_each(coalesce(op->'figli', '{}'::jsonb)) loop
      fk := figlio_fk(t, k);
      if fk is null then
        raise exception 'Dettaglio non previsto: % in %', k, t using errcode = '22023';
      end if;
      execute format('delete from public.%I where %I = $1', k, fk) using rid;
      if jsonb_array_length(righe) > 0 then
        righe := (select jsonb_agg(e || jsonb_build_object(fk, rid)) from jsonb_array_elements(righe) e);
        select string_agg(distinct key, ', ') into bad from jsonb_array_elements(righe) e, jsonb_object_keys(e) key
        where not exists (select 1 from information_schema.columns c
                          where c.table_schema = 'public' and c.table_name = k and c.column_name = key);
        if bad is not null then
          raise exception 'Campi sconosciuti in %: %', k, bad using errcode = '22023';
        end if;
        select string_agg(distinct quote_ident(key), ', ') into cols
          from jsonb_array_elements(righe) e, jsonb_object_keys(e) key;
        execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1)', k, cols)
          using righe;
      end if;
    end loop;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 7. Permessi (Row Level Security)
--    Titolare: legge e scrive tutto.
--    Dipendente: legge solo la propria agenda (e, come prima, le
--                proprie timbrature).
--    Senza login: nessun accesso.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['amministratori','conti','pagamenti','clienti','clienti_righe','fornitori','operatori',
    'elenchi','elenchi_voci','codici_iva','azienda','sedi','sedi_operatori','registro','variazioni','variazioni_operatori',
    'straordinari','straordinari_operatori','assenze','ispezioni','ispezioni_voti','preventivi','preventivi_righe',
    'fatture','fatture_righe','fatture_scadenze','fatture_preventivi','fatture_sdi_storia','acquisti','acquisti_righe',
    'acquisti_scadenze','movimenti','abbinamenti','cu','agenda']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists titolare on public.%I', t);
    execute format('create policy titolare on public.%I for all to authenticated using (is_titolare()) with check (is_titolare())', t);
    -- permessi espliciti (da fine ottobre 2026 Supabase non li concede più da solo alle tabelle nuove)
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

drop policy if exists agenda_dipendente on public.agenda;
create policy agenda_dipendente on public.agenda for select to authenticated
  using (operatore_id = mio_operatore());

grant usage, select on sequence public.abbinamenti_id_seq to authenticated, service_role;
revoke all on function public.salva_lotto(jsonb) from public, anon;
grant execute on function public.salva_lotto(jsonb) to authenticated;
grant execute on function public.figlio_fk(text, text) to authenticated;
grant execute on function public.is_titolare(), public.mio_operatore(), public.gps_attivo() to authenticated;

-- ---------------------------------------------------------------------
-- 8. Aggiornamenti in tempo reale
--    Ogni salvataggio aggiorna sempre la riga principale del record,
--    quindi basta seguire le tabelle principali (più l'agenda, che
--    l'app dipendenti segue per vedere subito i cambi di turno).
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['amministratori','conti','pagamenti','clienti','fornitori','operatori','elenchi','azienda',
      'sedi','registro','variazioni','straordinari','assenze','ispezioni','preventivi','fatture','acquisti','movimenti','cu','agenda']
    loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. Protezione delle funzioni
--    Nessuna funzione si può chiamare senza login; la funzione di
--    controllo delle timbrature la usa solo il trigger.
-- ---------------------------------------------------------------------
alter function public.tocca_updated_at() set search_path = public;
alter function public.tocca_aggiornato() set search_path = public;
alter function public.figlio_fk(text, text) set search_path = public;
revoke execute on function public.is_titolare(), public.mio_operatore(), public.gps_attivo(),
  public.controlla_timbratura(), public.figlio_fk(text, text), public.salva_lotto(jsonb) from public, anon;
revoke execute on function public.controlla_timbratura() from authenticated;
grant execute on function public.is_titolare(), public.mio_operatore(), public.gps_attivo(),
  public.figlio_fk(text, text), public.salva_lotto(jsonb) to authenticated;

-- Fatto. Verifica: deve restituire la tua email e il numero di record
-- ancora da trasferire dalla vecchia tabella.
select (select email_titolare from public.impostazioni) as titolare,
       (select count(*) from public.docs where col <> 'agenda') as record_nella_vecchia_tabella,
       (select count(*) from public.clienti) as clienti_nelle_nuove_tabelle;
