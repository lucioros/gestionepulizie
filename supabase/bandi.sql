-- =====================================================================
--  Gestione impresa pulizie · BANDI SUGGERITI (modulo Gare)
--  Come usarlo: Supabase → SQL Editor → New query → incolla tutto → Run.
--  Va eseguito DOPO schema_v2.sql e modulo_gare.sql. Si può rilanciare.
--
--  Ogni mattina il database scarica dalla Piattaforma di pubblicità a valore
--  legale di ANAC (pubblicitalegale.anticorruzione.it) i bandi, le indagini di
--  mercato e gli esiti dei servizi di pulizia (codici CPV 909…) pubblicati in
--  tutta Italia. L'app li confronta con zona, importi e requisiti dell'impresa.
--  Servono le estensioni "http" e "pg_cron", già disponibili su Supabase.
-- =====================================================================
set client_min_messages = warning;

do $$ begin
  create extension if not exists http with schema extensions;
exception when others then raise notice 'Estensione http non disponibile: la ricerca automatica non funzionerà (%).', sqlerrm;
end $$;
do $$ begin
  create extension if not exists pg_cron;
exception when others then raise notice 'Estensione pg_cron non disponibile: la ricerca va avviata a mano dall''app (%).', sqlerrm;
end $$;

create table if not exists public.bandi (
  id               text primary key,              -- idAvviso ANAC
  fonte            text not null default 'ANAC',
  tipologia        text,                          -- BANDI, INDAGINI_DI_MERCATO_…, RISULTATI, …
  momento          text not null,                 -- gara | indagine | preavviso | esito
  titolo           text,
  descrizione      text,
  ente             text,
  ente_cf          text,
  procedura        text,
  criterio         text,
  valore           numeric(14,2),                 -- valore stimato complessivo (tutti i lotti)
  valore_vincente  numeric(14,2),                 -- solo esiti
  aggiudicatari    text,                          -- solo esiti
  provincia        text,
  comune           text,
  pubblicazione    date,
  scadenza         date,
  ora_scadenza     text,
  lotti            jsonb not null default '[]'::jsonb,
  link_documenti   text,
  link_ted         text,
  url              text,
  stato            text not null default 'nuovo' check (stato in ('nuovo', 'visto', 'seguito', 'scartato', 'gara')),
  gara_id          text references public.gare (id) on delete set null,
  note             text,
  creato_il        timestamptz not null default now(),
  aggiornato_il    timestamptz not null default now()
);
create index if not exists bandi_pubblicazione on public.bandi (pubblicazione desc);

create table if not exists public.bandi_ricerche (
  id        bigint generated always as identity primary key,
  quando    timestamptz not null default now(),
  dal       date,
  al        date,
  letti     integer,
  nuovi     integer,
  errore    text
);

-- scarica una pagina dall'API (separata dal resto per poterla sostituire nei test)
do $$ begin
  if exists (select 1 from pg_extension where extname = 'http') then
    execute $f$
      create or replace function public.bandi_scarica(p_url text) returns jsonb
      language plpgsql security definer set search_path = public, extensions as $b$
      declare r record;
      begin
        perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '60');
        select status, content into r from extensions.http(('GET', p_url,
          array[extensions.http_header('Accept', 'application/json'), extensions.http_header('User-Agent', 'GestioneImpresaPulizie/1.0')], null, null)::extensions.http_request);
        if r.status <> 200 then raise exception 'ANAC ha risposto %', r.status; end if;
        return r.content::jsonb;
      end $b$ $f$;
  elsif not exists (select 1 from pg_proc where proname = 'bandi_scarica' and pronamespace = 'public'::regnamespace) then
    execute $f$
      create function public.bandi_scarica(p_url text) returns jsonb language plpgsql as $b$
      begin raise exception 'Estensione http non installata'; end $b$ $f$;
  end if;
end $$;
revoke all on function public.bandi_scarica(text) from public, anon, authenticated;

-- una data dell'API: "2026-12-09+01:00" oppure "2026-12-09T14:00:00.000+00:00"
create or replace function public.bandi_data(v text) returns date language sql immutable set search_path = public as $$
  select case when v is null or v = '' then null
              when v ~ 'T' then (v::timestamptz at time zone 'Europe/Rome')::date
              else left(v, 10)::date end
$$;

-- da un avviso ANAC al record della tabella bandi (null se non interessa)
create or replace function public.bandi_normalizza(x jsonb) returns public.bandi
language plpgsql stable set search_path = public as $$
declare
  tpl jsonb := x->'templates'->0->'template';
  sa jsonb; gen jsonb; items jsonb; b public.bandi; lotti jsonb;
begin
  b.id := x->>'idAvviso';
  if b.id is null or tpl is null then return null; end if;
  b.tipologia := x->>'tipologia';
  b.momento := case when b.tipologia = 'BANDI' then 'gara'
                    when b.tipologia like 'INDAGINI_DI_MERCATO%' or b.tipologia like 'CONSULTAZIONI%' then 'indagine'
                    when b.tipologia like 'AVVISI_DI_PREINFORMAZIONE%' then 'preavviso'
                    when b.tipologia = 'RISULTATI' then 'esito' end;
  if b.momento is null then return null; end if;      -- modifiche contrattuali, proroghe, …
  select s->'fields' into sa from jsonb_array_elements(tpl->'sections') s where s->>'name' like 'SEZ. A%' limit 1;
  select s->'fields' into gen from jsonb_array_elements(tpl->'sections') s where s->>'name' like 'SEZ. B%' limit 1;
  select coalesce(jsonb_agg(i), '[]') into items from jsonb_array_elements(tpl->'sections') s, jsonb_array_elements(coalesce(s->'items', '[]')) i
   where s->>'name' like 'SEZ. C%';
  b.ente := sa->'soggetti_sa'->0->>'denominazione_amministrazione';
  b.ente_cf := sa->'soggetti_sa'->0->>'codice_fiscale';
  b.procedura := gen->>'tipo_procedura_aggiudicazione';
  b.titolo := left(coalesce(nullif(tpl->'metadata'->>'titolo', ''), nullif(tpl->'metadata'->>'descrizione', ''), items->0->>'descrizione', '(senza titolo)'), 500);
  b.descrizione := left(coalesce(tpl->'metadata'->>'descrizione', ''), 2000);
  b.link_ted := tpl->'metadata'->>'link_eform_ted';
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cig', i->>'cig',
      'descrizione', left(i->>'descrizione', 600),
      'cpv', i->>'cpv',
      'valore', coalesce(i->'valore_complessivo_stimato', i->'valore_affidamento'),
      'durata', case when i->>'durata' ~ '^\d+$' then (i->>'durata')::int when i->>'durata_contratto' ~ '^\d+$' then (i->>'durata_contratto')::int end,
      'provincia', i->>'luogo_nuts',
      'comune', initcap(i->>'luogo_istat'),
      'scadenza', public.bandi_data(coalesce(i->>'termine_ricezione', i->>'termine_invito')),
      'criterio', i->>'criteri_aggiudicazione',
      'vincente', i->'valore_offerta_vincente',
      'aggiudicatari', nullif(concat_ws(', ',
          (select string_agg(distinct v #>> '{}', ', ') from jsonb_path_query(i, 'lax $.aggiudicatari.**.denominazione') v),
          (select string_agg(distinct v #>> '{}', ', ') from jsonb_path_query(i, 'lax $.aggiudicatari_ad.**.denominazione') v)), '')
    )) order by n), '[]')
    into lotti from jsonb_array_elements(items) with ordinality t(i, n);
  b.lotti := lotti;
  select sum((l->>'valore')::numeric), sum((l->>'vincente')::numeric), string_agg(distinct l->>'aggiudicatari', ', '),
         min((l->>'scadenza')::date), min(l->>'criterio')
    into b.valore, b.valore_vincente, b.aggiudicatari, b.scadenza, b.criterio from jsonb_array_elements(lotti) l;
  b.provincia := lotti->0->>'provincia';
  b.comune := lotti->0->>'comune';
  b.pubblicazione := public.bandi_data(x->>'dataPubblicazione');
  if x->>'dataScadenza' is not null then
    b.scadenza := public.bandi_data(x->>'dataScadenza');
    b.ora_scadenza := to_char((x->>'dataScadenza')::timestamptz at time zone 'Europe/Rome', 'HH24:MI');
  end if;
  b.link_documenti := coalesce(gen->>'documenti_di_gara_link', items->0->>'documenti_di_gara_link');
  b.url := 'https://pubblicitalegale.anticorruzione.it/' || case b.momento when 'gara' then 'bandi' when 'esito' then 'esiti' else 'avvisi' end || '/' || b.id;
  b.fonte := 'ANAC'; b.stato := 'nuovo'; b.lotti := coalesce(b.lotti, '[]');
  return b;
end $$;

-- importa una risposta dell'API; restituisce {letti, nuovi}
create or replace function public.bandi_importa(j jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; b public.bandi; n_letti int := 0; n_nuovi int := 0; ins boolean;
begin
  for x in select * from jsonb_array_elements(coalesce(j->'content', '[]')) loop
    n_letti := n_letti + 1;
    b := public.bandi_normalizza(x);
    if b.id is null then continue; end if;
    insert into public.bandi as t (id, fonte, tipologia, momento, titolo, descrizione, ente, ente_cf, procedura, criterio, valore, valore_vincente,
        aggiudicatari, provincia, comune, pubblicazione, scadenza, ora_scadenza, lotti, link_documenti, link_ted, url)
    values (b.id, b.fonte, b.tipologia, b.momento, b.titolo, b.descrizione, b.ente, b.ente_cf, b.procedura, b.criterio, b.valore, b.valore_vincente,
        b.aggiudicatari, b.provincia, b.comune, b.pubblicazione, b.scadenza, b.ora_scadenza, b.lotti, b.link_documenti, b.link_ted, b.url)
    on conflict (id) do update set titolo = excluded.titolo, descrizione = excluded.descrizione, ente = excluded.ente, procedura = excluded.procedura,
        criterio = excluded.criterio, valore = excluded.valore, valore_vincente = excluded.valore_vincente, aggiudicatari = excluded.aggiudicatari,
        provincia = excluded.provincia, comune = excluded.comune, scadenza = excluded.scadenza, ora_scadenza = excluded.ora_scadenza,
        lotti = excluded.lotti, link_documenti = excluded.link_documenti, link_ted = excluded.link_ted, aggiornato_il = now()
    returning (xmax = 0) into ins;
    if ins then n_nuovi := n_nuovi + 1; end if;
  end loop;
  return jsonb_build_object('letti', n_letti, 'nuovi', n_nuovi);
end $$;
revoke all on function public.bandi_importa(jsonb) from public, anon, authenticated;

-- la ricerca: dagli ultimi p_giorni a oggi, a finestre di 10 giorni; codici CPV dalle impostazioni dell'app
create or replace function public.cerca_bandi(p_giorni integer default 3) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cpv text; da date; a date; fine date := (now() at time zone 'Europe/Rome')::date; j jsonb; r jsonb;
  tot_letti int := 0; tot_nuovi int := 0; err text; avviso text := null;
begin
  if auth.uid() is not null and not public.is_titolare() then raise exception 'Solo il titolare può cercare i bandi'; end if;
  p_giorni := least(greatest(coalesce(p_giorni, 3), 1), 90);
  select string_agg(c, ',') into cpv from (
    select regexp_replace(v #>> '{}', '\D', '', 'g') c from public.elenchi e, jsonb_array_elements(coalesce(e.extra->'cpv', '[]')) v
     where e.id = 'bandiRicerca') z where length(c) between 3 and 8;
  cpv := coalesce(cpv, '909');
  da := fine - p_giorni;
  begin
    while da <= fine loop
      a := least(da + 9, fine);
      j := public.bandi_scarica('https://pubblicitalegale.anticorruzione.it/api/v0/avvisi-full-text-specializzata?page=0&pageSize=1000'
        || '&dataPubblicazioneStart=' || to_char(da, 'DD/MM/YYYY') || '&dataPubblicazioneEnd=' || to_char(a, 'DD/MM/YYYY')
        || '&cpv=' || cpv || '&sortField=dataPubblicazione&sortDirection=desc&operatore=AND');
      r := public.bandi_importa(j);
      tot_letti := tot_letti + (r->>'letti')::int; tot_nuovi := tot_nuovi + (r->>'nuovi')::int;
      if coalesce((j->>'count')::numeric, 0) > jsonb_array_length(coalesce(j->'content', '[]')) then
        avviso := 'Troppi avvisi in un solo periodo: alcuni potrebbero mancare';
      end if;
      da := a + 1;
    end loop;
  exception when others then err := sqlerrm;
  end;
  -- pulizia: avvisi vecchi non seguiti
  delete from public.bandi where pubblicazione < fine - 180 and stato in ('nuovo', 'visto', 'scartato');
  delete from public.bandi_ricerche where quando < now() - interval '60 days';
  insert into public.bandi_ricerche (dal, al, letti, nuovi, errore) values (fine - p_giorni, fine, tot_letti, tot_nuovi, coalesce(err, avviso));
  return jsonb_build_object('letti', tot_letti, 'nuovi', tot_nuovi, 'errore', err, 'avviso', avviso);
end $$;
revoke all on function public.cerca_bandi(integer) from public, anon;
grant execute on function public.cerca_bandi(integer) to authenticated;

-- permessi: solo il titolare
do $$
declare t text;
begin
  foreach t in array array['bandi', 'bandi_ricerche'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists titolare on public.%I', t);
    execute format('create policy titolare on public.%I for all to authenticated using (is_titolare()) with check (is_titolare())', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
drop trigger if exists bandi_aggiornato on public.bandi;
create trigger bandi_aggiornato before update on public.bandi for each row execute function public.tocca_aggiornato();

-- ogni mattina alle 6:20 (ora italiana d'inverno; 7:20 d'estate), ultimi 3 giorni
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'cerca-bandi';
    perform cron.schedule('cerca-bandi', '20 5 * * *', 'select public.cerca_bandi(3)');
  end if;
end $$;

-- Fatto. Prima ricerca degli ultimi 30 giorni (richiede qualche secondo):
-- select public.cerca_bandi(30);
