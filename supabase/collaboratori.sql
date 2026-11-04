-- =====================================================================
-- Collaboratori: altre persone che entrano nel gestionale con nome utente
-- e password, ognuna solo sui moduli che il titolare le assegna.
--
-- Da eseguire in Supabase (SQL Editor) DOPO schema.sql, schema_v2.sql,
-- modulo_gare.sql, contabilita.sql e bandi.sql. Si può rieseguire: se
-- riesegui uno di quegli script, riesegui poi anche questo.
--
-- Come funziona
-- - Il titolare crea il collaboratore dall'app (Impostazioni → Collaboratori).
--   L'account viene creato qui nel database: non serve un'email vera, il
--   nome utente diventa l'indirizzo interno <nomeutente>@utenti.invalid
--   (dominio riservato, nessuna email viene mai inviata).
-- - Ogni tabella ha in "permessi_archivi" i moduli che la possono leggere
--   e quelli che la possono modificare. "*" vuol dire qualsiasi
--   collaboratore attivo. Il titolare può sempre tutto.
-- - I dati di base (clienti, sedi, dipendenti, turni, fornitori, elenchi)
--   li leggono tutti i collaboratori, perché servono in quasi ogni modulo
--   (scegliere il cliente in una fattura, i dipendenti in un turno...).
--   Li modifica solo chi ha il modulo relativo.
-- - Impostazioni, dati dell'impresa e gestione dei collaboratori restano
--   del solo titolare.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Collaboratori
-- ---------------------------------------------------------------------
create table if not exists public.collaboratori (
  id            uuid primary key,              -- lo stesso id dell'utente di accesso
  utente        text not null unique check (utente ~ '^[a-z0-9][a-z0-9._-]{2,29}$'),
  nome          text not null,
  moduli        text[] not null default '{}',
  attivo        boolean not null default true,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);
drop trigger if exists collaboratori_aggiornato on public.collaboratori;
create trigger collaboratori_aggiornato before update on public.collaboratori
  for each row execute function public.tocca_aggiornato();

-- moduli che si possono assegnare (i menu dell'app, tranne Oggi e Impostazioni)
create or replace function public.moduli_collaboratori() returns text[]
language sql immutable set search_path = public as $$
  select array['lavori','clienti','personale','fatture','gare','contabilita']
$$;

-- ---------------------------------------------------------------------
-- 2. Chi può leggere e modificare ogni tabella
-- ---------------------------------------------------------------------
create table if not exists public.permessi_archivi (
  tab    text primary key,
  leggi  text[] not null,   -- moduli che leggono ('*' = ogni collaboratore)
  scrivi text[] not null,   -- moduli che modificano ('{}' = solo il titolare)
  modulo text               -- modulo a pagamento che deve essere attivo (es. gare)
);
insert into public.permessi_archivi (tab, leggi, scrivi, modulo) values
  -- dati dell'impresa e impostazioni: li legge chiunque, li cambia il titolare
  ('azienda',              '{*}', '{}', null),
  ('pagamenti',            '{*}', '{}', null),
  ('elenchi',              '{*}', '{*}', null),
  ('elenchi_voci',         '{*}', '{*}', null),
  ('codici_iva',           '{*}', '{*}', null),
  -- anagrafiche comuni
  ('clienti',              '{*}', '{clienti,fatture,gare}', null),
  ('clienti_righe',        '{*}', '{clienti,fatture,gare}', null),
  ('amministratori',       '{*}', '{clienti}', null),
  ('sedi',                 '{*}', '{clienti,lavori,gare}', null),
  ('sedi_operatori',       '{*}', '{clienti,lavori,gare}', null),
  ('operatori',            '{*}', '{personale}', null),
  ('fornitori',            '{*}', '{fatture,contabilita}', null),
  ('conti',                '{*}', '{contabilita}', null),
  -- turni: li leggono tutti perché l'agenda dei dipendenti si calcola da qui
  ('registro',             '{*}', '{lavori}', null),
  ('variazioni',           '{*}', '{lavori}', null),
  ('variazioni_operatori', '{*}', '{lavori}', null),
  ('straordinari',         '{*}', '{lavori}', null),
  ('straordinari_operatori','{*}', '{lavori}', null),
  ('assenze',              '{*}', '{personale,lavori}', null),
  ('agenda',               '{*}', '{lavori,clienti,personale}', null),
  ('ispezioni',            '{lavori,clienti}', '{lavori}', null),
  ('ispezioni_voti',       '{lavori,clienti}', '{lavori}', null),
  ('timbrature',           '{personale,lavori}', '{personale}', null),
  -- preventivi
  ('preventivi',           '{clienti,fatture,lavori}', '{clienti,fatture}', null),
  ('preventivi_righe',     '{clienti,fatture,lavori}', '{clienti,fatture}', null),
  -- fatture, incassi e contabilità
  ('fatture',              '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('fatture_righe',        '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('fatture_scadenze',     '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('fatture_preventivi',   '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('fatture_sdi_storia',   '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('acquisti',             '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('acquisti_righe',       '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('acquisti_scadenze',    '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('cu',                   '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('movimenti',            '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('abbinamenti',          '{fatture,contabilita}', '{fatture,contabilita}', null),
  ('conti_economici',      '{fatture,contabilita}', '{contabilita}', null),
  ('scritture',            '{contabilita}', '{contabilita}', null),
  -- gare
  ('gare',                 '{gare}', '{gare}', 'gare'),
  ('gare_voci',            '{gare}', '{gare}', 'gare'),
  ('gare_personale',       '{gare}', '{gare}', 'gare'),
  ('gare_documenti',       '{gare}', '{gare}', 'gare'),
  ('gare_concorrenti',     '{gare}', '{gare}', 'gare'),
  ('costi_lavoro',         '{gare}', '{gare}', 'gare'),
  ('costi_lavoro_livelli', '{gare}', '{gare}', 'gare'),
  ('documenti_impresa',    '{gare}', '{gare}', 'gare'),
  ('modelli_gara',         '{gare}', '{gare}', 'gare'),
  ('bandi',                '{gare}', '{gare}', null),
  ('bandi_ricerche',       '{gare}', '{gare}', null)
on conflict (tab) do update set leggi = excluded.leggi, scrivi = excluded.scrivi, modulo = excluded.modulo;

-- moduli del collaboratore collegato (null se non è un collaboratore attivo)
create or replace function public.miei_moduli() returns text[]
language sql stable security definer set search_path = public as $$
  select moduli from collaboratori where id = auth.uid() and attivo
$$;

-- può leggere (p_scrivi = false) o modificare (true) la tabella?
create or replace function public.puo(p_tab text, p_scrivi boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select is_titolare() or coalesce((
    select (case when p_scrivi then a.scrivi else a.leggi end) && (c.moduli || '{*}'::text[])
    from permessi_archivi a, collaboratori c
    where a.tab = p_tab and c.id = auth.uid() and c.attivo), false)
$$;

-- ---------------------------------------------------------------------
-- 3. Regole di accesso (Row Level Security) secondo la tabella dei permessi
--    Sostituiscono le regole "solo titolare"; quelle per l'app dipendenti
--    (agenda e timbrature del dipendente) restano come sono.
-- ---------------------------------------------------------------------
do $$
declare r record; cond_l text; cond_s text;
begin
  for r in select a.tab, a.modulo from permessi_archivi a
           where exists (select 1 from information_schema.tables t where t.table_schema = 'public' and t.table_name = a.tab)
  loop
    cond_l := format('(select public.puo(%L, false))', r.tab);
    cond_s := format('(select public.puo(%L, true))', r.tab);
    if r.modulo is not null then
      cond_l := cond_l || format(' and public.modulo_attivo(%L)', r.modulo);
      cond_s := cond_s || format(' and public.modulo_attivo(%L)', r.modulo);
    end if;
    execute format('alter table public.%I enable row level security', r.tab);
    execute format('drop policy if exists titolare on public.%I', r.tab);
    execute format('drop policy if exists timb_titolare on public.%I', r.tab);
    execute format('drop policy if exists accesso_lettura on public.%I', r.tab);
    execute format('drop policy if exists accesso_inserimento on public.%I', r.tab);
    execute format('drop policy if exists accesso_modifica on public.%I', r.tab);
    execute format('drop policy if exists accesso_eliminazione on public.%I', r.tab);
    execute format('create policy accesso_lettura on public.%I for select to authenticated using (%s)', r.tab, cond_l);
    execute format('create policy accesso_inserimento on public.%I for insert to authenticated with check (%s)', r.tab, cond_s);
    execute format('create policy accesso_modifica on public.%I for update to authenticated using (%s) with check (%s)', r.tab, cond_s, cond_s);
    execute format('create policy accesso_eliminazione on public.%I for delete to authenticated using (%s)', r.tab, cond_s);
  end loop;
end $$;

-- impostazioni (moduli attivi, GPS): le legge anche il collaboratore, le cambia il titolare
drop policy if exists imp_collaboratori on public.impostazioni;
create policy imp_collaboratori on public.impostazioni for select to authenticated
  using ((select public.miei_moduli()) is not null);

-- collaboratori: il titolare vede tutti, il collaboratore solo sé stesso;
-- si modificano solo con le funzioni qui sotto
alter table public.collaboratori enable row level security;
drop policy if exists lettura on public.collaboratori;
create policy lettura on public.collaboratori for select to authenticated
  using (is_titolare() or id = auth.uid());
revoke all on public.collaboratori from anon, authenticated;
grant select on public.collaboratori to authenticated;
grant select, insert, update, delete on public.collaboratori to service_role;

alter table public.permessi_archivi enable row level security;
drop policy if exists lettura on public.permessi_archivi;
create policy lettura on public.permessi_archivi for select to authenticated using (true);
revoke all on public.permessi_archivi from anon, authenticated;
grant select on public.permessi_archivi to authenticated;
grant select, insert, update, delete on public.permessi_archivi to service_role;

-- file allegati (documenti delle gare, modelli): titolare e collaboratori attivi
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    drop policy if exists allegati_titolare on storage.objects;
    drop policy if exists allegati_accesso on storage.objects;
    create policy allegati_accesso on storage.objects for all to authenticated
      using (bucket_id = 'allegati' and (public.is_titolare() or (select public.miei_moduli()) is not null))
      with check (bucket_id = 'allegati' and (public.is_titolare() or (select public.miei_moduli()) is not null));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Funzioni già esistenti che controllavano "solo il titolare"
--    (si aggiornano sul posto, così il resto della funzione non cambia)
-- ---------------------------------------------------------------------
do $$
declare d text;
begin
  -- salvataggio dal gestionale: ora anche i collaboratori; le regole del
  -- punto 3 decidono poi tabella per tabella
  d := pg_get_functiondef('public.salva_lotto(jsonb)'::regprocedure);
  if position('if not is_titolare() then' in d) > 0 then
    d := replace(d, 'if not is_titolare() then', 'if not (is_titolare() or miei_moduli() is not null) then');
    d := replace(d, 'Solo il titolare può modificare i dati', 'Non hai accesso ai dati del gestionale');
    execute d;
  end if;
  -- correzione delle timbrature: titolare o collaboratore con il modulo Personale
  d := pg_get_functiondef('public.controlla_timbratura()'::regprocedure);
  if position('if is_titolare() then' in d) > 0 then
    execute replace(d, 'if is_titolare() then', 'if public.puo(''timbrature'', true) then');
  end if;
  -- ricerca dei bandi: titolare o collaboratore con il modulo Gare
  if to_regprocedure('public.cerca_bandi(integer)') is not null then
    d := pg_get_functiondef('public.cerca_bandi(integer)'::regprocedure);
    if position('not public.is_titolare()' in d) > 0 then
      d := replace(d, 'not public.is_titolare()', 'not public.puo(''bandi'', true)');
      d := replace(d, 'Solo il titolare può cercare i bandi', 'Serve il modulo Gare per cercare i bandi');
      execute d;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Profilo di chi è collegato (lo legge l'app all'accesso)
-- ---------------------------------------------------------------------
create or replace function public.mio_profilo() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c collaboratori;
begin
  if is_titolare() then return jsonb_build_object('ruolo', 'titolare'); end if;
  select * into c from collaboratori where id = auth.uid();
  if found and c.attivo then
    return jsonb_build_object('ruolo', 'collaboratore', 'nome', c.nome, 'utente', c.utente,
      'moduli', to_jsonb(c.moduli));
  end if;
  if found then return jsonb_build_object('ruolo', 'disattivato', 'nome', c.nome); end if;
  return jsonb_build_object('ruolo', null);
end $$;

-- ---------------------------------------------------------------------
-- 6. Gestione dei collaboratori (solo il titolare)
-- ---------------------------------------------------------------------
create or replace function public.controlla_moduli(p_moduli text[]) returns text[]
language plpgsql immutable set search_path = public as $$
declare bad text;
begin
  select string_agg(m, ', ') into bad from unnest(coalesce(p_moduli, '{}')) m
  where not m = any(moduli_collaboratori());
  if bad is not null then raise exception 'Moduli non previsti: %', bad using errcode = '22023'; end if;
  return array(select distinct m from unnest(coalesce(p_moduli, '{}')) m order by m);
end $$;

create or replace function public.solo_titolare() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_titolare() then
    raise exception 'Solo il titolare può gestire i collaboratori' using errcode = '42501';
  end if;
end $$;

create or replace function public.elenco_collaboratori()
returns table (id uuid, utente text, nome text, moduli text[], attivo boolean, creato_il timestamptz, ultimo_accesso timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform solo_titolare();
  return query select c.id, c.utente, c.nome, c.moduli, c.attivo, c.creato_il, u.last_sign_in_at
    from collaboratori c left join auth.users u on u.id = c.id order by c.nome;
end $$;

create or replace function public.crea_collaboratore(p_utente text, p_nome text, p_password text, p_moduli text[])
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := gen_random_uuid(); u text := lower(trim(p_utente)); em text; mods text[];
begin
  perform solo_titolare();
  if u !~ '^[a-z0-9][a-z0-9._-]{2,29}$' then
    raise exception 'Nome utente non valido: da 3 a 30 caratteri tra lettere minuscole, numeri, punto, trattino e trattino basso, senza spazi' using errcode = '22023';
  end if;
  if coalesce(trim(p_nome), '') = '' then raise exception 'Scrivi nome e cognome del collaboratore' using errcode = '22023'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'La password deve avere almeno 8 caratteri' using errcode = '22023'; end if;
  mods := controlla_moduli(p_moduli);
  em := u || '@utenti.invalid';
  if exists (select 1 from collaboratori where utente = u) or exists (select 1 from auth.users where lower(email) = em) then
    raise exception 'Il nome utente "%" è già usato: scegline un altro', u using errcode = '23505';
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('nome', trim(p_nome), 'collaboratore', true),
      now(), now(), '', '', '', '');
  insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (uid::text, uid, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true, 'phone_verified', false),
      'email', now(), now());
  insert into collaboratori (id, utente, nome, moduli) values (uid, u, trim(p_nome), mods);
  return uid;
end $$;

create or replace function public.aggiorna_collaboratore(p_id uuid, p_nome text, p_moduli text[], p_attivo boolean)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  perform solo_titolare();
  if coalesce(trim(p_nome), '') = '' then raise exception 'Scrivi nome e cognome del collaboratore' using errcode = '22023'; end if;
  update collaboratori set nome = trim(p_nome), moduli = controlla_moduli(p_moduli), attivo = coalesce(p_attivo, true)
    where id = p_id;
  if not found then raise exception 'Collaboratore non trovato' using errcode = 'P0002'; end if;
  -- disattivato: non può più entrare e viene fatto uscire dai dispositivi
  update auth.users set banned_until = case when coalesce(p_attivo, true) then null else timestamptz '2999-12-31' end,
    updated_at = now() where id = p_id;
  if not coalesce(p_attivo, true) then delete from auth.sessions where user_id = p_id; end if;
end $$;

create or replace function public.password_collaboratore(p_id uuid, p_password text)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  perform solo_titolare();
  if length(coalesce(p_password, '')) < 8 then raise exception 'La password deve avere almeno 8 caratteri' using errcode = '22023'; end if;
  if not exists (select 1 from collaboratori where id = p_id) then raise exception 'Collaboratore non trovato' using errcode = 'P0002'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
    where id = p_id;
  delete from auth.sessions where user_id = p_id;   -- deve rientrare con la nuova password
end $$;

create or replace function public.elimina_collaboratore(p_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  perform solo_titolare();
  if not exists (select 1 from collaboratori where id = p_id) then raise exception 'Collaboratore non trovato' using errcode = 'P0002'; end if;
  delete from collaboratori where id = p_id;
  -- solo account creati come collaboratori: mai quello del titolare
  delete from auth.users where id = p_id and email like '%@utenti.invalid';
end $$;

-- numero progressivo dei file della fattura elettronica: lo avanza anche chi ha
-- il modulo Fatture, senza poter cambiare gli altri dati dell'impresa
create or replace function public.prossimo_progressivo() returns integer
language plpgsql volatile security definer set search_path = public as $$
declare n integer;
begin
  if not public.puo('fatture', true) then
    raise exception 'Serve il modulo Fatture' using errcode = '42501';
  end if;
  update azienda set progressivo = coalesce(progressivo, 0) + 1 where id = 'azienda' returning progressivo into n;
  if n is null then raise exception 'Inserisci prima i dati della tua impresa' using errcode = 'P0002'; end if;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 7. Protezione delle funzioni
-- ---------------------------------------------------------------------
alter function public.tocca_aggiornato() set search_path = public;
revoke execute on function public.miei_moduli(), public.puo(text, boolean), public.mio_profilo(),
  public.moduli_collaboratori(), public.controlla_moduli(text[]), public.solo_titolare(),
  public.elenco_collaboratori(), public.crea_collaboratore(text, text, text, text[]),
  public.aggiorna_collaboratore(uuid, text, text[], boolean), public.password_collaboratore(uuid, text),
  public.elimina_collaboratore(uuid), public.prossimo_progressivo() from public, anon;
grant execute on function public.miei_moduli(), public.puo(text, boolean), public.mio_profilo(),
  public.moduli_collaboratori(), public.elenco_collaboratori(), public.crea_collaboratore(text, text, text, text[]),
  public.aggiorna_collaboratore(uuid, text, text[], boolean), public.password_collaboratore(uuid, text),
  public.elimina_collaboratore(uuid), public.prossimo_progressivo() to authenticated;
revoke execute on function public.controlla_moduli(text[]), public.solo_titolare() from authenticated;

-- Fatto. Verifica: deve comparire "titolare" (eseguito dal SQL Editor compare null,
-- perché lì non sei collegato come utente dell'app) e il numero di tabelle protette.
select public.mio_profilo() as profilo,
       (select count(*) from pg_policies where policyname = 'accesso_lettura') as tabelle_con_permessi;
