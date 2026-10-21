# Registro Pulizie

Gestionale per imprese di pulizia di uffici e condomini, con app per i dipendenti.

- **Gestionale del titolare**: https://lucioros.github.io/gestionepulizie/
- **App dipendenti** (installabile sul telefono): https://lucioros.github.io/gestionepulizie/dipendenti/

I dati stanno nel database Supabase. Il codice di questo repository non contiene dati né chiavi segrete.

## Contenuto

| Percorso | Cosa contiene |
|---|---|
| `index.html` | Gestionale del titolare: turni, agenda, clienti, personale, preventivi, qualità, fatture, prima nota, partite aperte, mastrini, timbrature |
| `dipendenti/` | App dipendenti: turni di oggi e dei prossimi giorni, timbratura di inizio e fine lavoro, ore del mese |
| `supabase/schema.sql` | Impostazioni, timbrature e permessi di base (da eseguire per primo) |
| `supabase/schema_v2.sql` | Tabelle collegate di tutti gli archivi, funzioni di salvataggio e permessi (da eseguire dopo) |
| `config.js` | Indirizzo del progetto Supabase e chiave pubblica (anon) |
| `vendor/` | Librerie Supabase e JSZip (MIT), incluse per non dipendere da CDN esterni |

## Messa in funzione (una volta sola)

### 1. Database
1. Supabase → **SQL Editor** → **New query**.
2. Incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**. L'ultima riga mostra l'email del titolare (`luciorosalba@gmail.com`). Se vuoi usarne un'altra, cambiala nello script (sezione 1) e rilancialo.
3. Nuova query: incolla tutto il contenuto di `supabase/schema_v2.sql` e premi **Run**. Crea le tabelle collegate e le funzioni che usa il gestionale.

Entrambi gli script si possono rilanciare senza perdere dati. Se rilanci `schema.sql`, rilancia sempre anche `schema_v2.sql` subito dopo: il secondo aggiorna alcune funzioni del primo per farle lavorare sulle nuove tabelle.

### 2. Accesso con email
1. Supabase → **Authentication → URL Configuration**:
   - **Site URL**: `https://lucioros.github.io/gestionepulizie/`
   - **Redirect URLs**: aggiungi `https://lucioros.github.io/gestionepulizie/**`
2. **Authentication → Sign In / Providers → Email**: lascia attivo **Confirm email**. Senza la conferma, chiunque potrebbe registrarsi con l'email di un altro.

### 3. Pubblicazione su GitHub Pages
GitHub → repository → **Settings → Pages** → *Build and deployment*: **Deploy from a branch**, branch **main**, cartella **/ (root)** → **Save**. Dopo un paio di minuti il sito è online.

### 4. Primo accesso del titolare
1. Apri il gestionale, scrivi email e password e premi **Crea account**.
2. Conferma l'email dal messaggio ricevuto, poi torna al gestionale ed entra.
3. Per portare i dati dall'app su Claude: lì premi **Esporta dati per il nuovo gestionale** (in basso a sinistra), poi qui vai in **Impostazioni e app dipendenti → Importa dati**.

### 5. Dipendenti
1. Nella scheda di ogni dipendente compila **Email per l'app dipendenti**.
2. Manda al dipendente il link dell'app dipendenti. Lui sceglie **Prima volta? Crea account** con quella email, conferma l'email ed entra.
3. Sul telefono: Android/Chrome → **Installa app**; iPhone/Safari → **Condividi → Aggiungi alla schermata Home**.

## Il database

Ogni archivio ha la sua tabella, collegata alle altre con chiavi esterne:

- **Anagrafiche**: `clienti` (con `clienti_righe`, le righe abituali in fattura), `amministratori`, `fornitori`, `operatori`, `conti`, `pagamenti`, `azienda`, `elenchi` (con `elenchi_voci` e `codici_iva`).
- **Operatività**: `sedi` (con `sedi_operatori`, la squadra), `registro` (turni svolti o saltati), `variazioni` e `straordinari` (con le rispettive squadre), `assenze`, `ispezioni` (con `ispezioni_voti`), `preventivi` (con `preventivi_righe`).
- **Contabilità**: `fatture` (con `fatture_righe`, `fatture_scadenze`, `fatture_preventivi` e `fatture_sdi_storia`), `acquisti` (con `acquisti_righe` e `acquisti_scadenze`), `movimenti` di prima nota, `abbinamenti` (quale incasso, pagamento o nota di credito salda quale fattura e quale rata), `cu`.
- **App dipendenti**: `agenda` (turni pubblicati per ogni dipendente) e `timbrature`.

Il database stesso impedisce i dati incoerenti. Non si può eliminare un cliente che ha sedi o fatture, né registrare una fattura per un cliente che non esiste. Ogni salvataggio passa dalla funzione `salva_lotto`, che scrive il record e tutte le sue righe in un'unica transazione: o va a buon fine tutto o niente. Gli eventuali campi che l'app aggiungerà in futuro finiscono nella colonna `extra` (JSON) finché non avranno una colonna propria.

Per interrogare i dati usa le tabelle direttamente da Supabase (Table Editor o SQL Editor), ad esempio:

```sql
select f.numero, f.data, c.nome, sum(r.qta * r.prezzo) as imponibile
from fatture f
join clienti c on c.id = f.cliente_id
join fatture_righe r on r.fattura_id = f.id
group by f.id, c.nome
order by f.data desc;
```

### Passaggio dalla vecchia tabella `docs`

Fino a ottobre 2026 tutti i dati stavano nella tabella `docs` (un record JSON per riga). Dopo aver eseguito `schema_v2.sql`, alla prima apertura il gestionale propone **Trasferisci i dati**. Il trasferimento:
- copia tutto nelle nuove tabelle senza toccare `docs`, che resta come copia di sicurezza;
- quando un documento fa riferimento a un dato eliminato (per esempio una fattura di un cliente cancellato), crea un record "recuperato" al suo posto, così nessun documento va perso;
- alla fine mostra quanti record sono stati trasferiti per archivio e l'elenco delle sistemazioni fatte.

Da **Impostazioni → Ripeti il trasferimento** si possono aggiungere i record che mancassero, senza toccare quelli già presenti. Quando avrai verificato i dati per qualche settimana potrai eliminare la vecchia tabella con `drop table public.docs;`.

## Come funziona

- **Tipi di pagamento e incasso** (Contabilità → Tipi di pagamento): rimessa diretta, bonifico, RiBa, SDD, contanti, assegno, POS, PagoPA e tutti gli strumenti della fattura elettronica (MP01–MP23). Ogni tipo definisce i giorni delle rate, il calcolo da data fattura o fine mese, il giorno fisso, i mesi esclusi, l'IVA alla prima rata e il conto predefinito. Clienti e fornitori hanno il loro tipo; le fatture lo propongono e calcolano le rate, modificabili a mano. Lo **Scadenzario** elenca tutte le rate aperte.

- **Permessi**: il titolare (l'email in `impostazioni`) legge e scrive tutto. Ogni dipendente legge solo la propria agenda e le proprie timbrature, e può solo aggiungere timbrature proprie. Lo impone il database stesso (Row Level Security), non l'app.
- **Agenda dei dipendenti**: il gestionale pubblica per ogni dipendente con email i turni da ieri ai prossimi 14 giorni. Lo rifà ogni volta che cambi turni, sedi o assenze e ogni 15 minuti finché resta aperto. Se nessuno apre il gestionale per più di due settimane, l'agenda dei dipendenti si esaurisce.
- **Timbrature**: l'ora è quella del server, non del telefono. Si possono timbrare solo i turni della propria agenda, e solo il giorno stesso. La fine richiede prima l'inizio. Le correzioni del titolare restano segnate come "corretta".
- **Posizione GPS**: è disattivata finché non la attivi in Impostazioni. In Italia è un controllo a distanza (art. 4 Statuto dei Lavoratori): verifica prima con il consulente del lavoro.

## Fattura elettronica

1. **Impostazioni → Dati della tua impresa**: denominazione, partita IVA, regime fiscale, sede, IBAN, REA. Finiscono in ogni fattura.
2. Nelle schede **clienti** servono partita IVA (aziende) o codice fiscale (condomini e privati), indirizzo, CAP, comune e il codice destinatario SdI (o la PEC). Partita IVA e codice fiscale vengono controllati.
3. In **Fatture di vendita** il pulsante **XML** controlla i dati obbligatori e genera il file FatturaPA (formato 1.2, specifiche 1.9). Ogni riga ha la sua aliquota o natura (N6.7 inversione contabile, N1, N2.2...). Il file include anche la ritenuta 4% dei condomini (causale W), la scissione dei pagamenti, il bollo virtuale, le scadenze con IBAN, l'ordine/CIG/CUP e la fattura collegata alle note di credito. **Scarica XML da inviare** crea uno zip con tutte le fatture ancora da trasmettere.
4. Carica i file sul portale **Fatture e Corrispettivi** dell'Agenzia delle Entrate (Fatturazione elettronica → Trasmissione) o dal tuo intermediario, **entro 12 giorni** dalla data della fattura.
5. Aggiorna lo **stato SdI** (inviata, consegnata, non consegnata, scartata). Le fatture trasmesse non si possono eliminare: si corregge con una nota di credito. In **Oggi** compaiono gli avvisi per scarti e ritardi.
6. **Copia di cortesia**: versione stampabile o PDF da mandare al cliente, obbligatoria di fatto quando la fattura resta nell'area riservata (codice 0000000).
7. **Imposta di bollo**: in Impostazioni c'è il riepilogo trimestrale (2 € per fattura con più di 77,47 € senza IVA, F24 codici 2521–2524). Fa fede il calcolo dell'Agenzia nel portale.
8. **Fatture d'acquisto → Importa XML**: carica i file .xml, .xml.p7m o .zip scaricati dal portale. Crea il fornitore se manca e registra righe, IVA, ritenuta e scadenze, saltando i doppioni.

Prima di usarla in produzione fai controllare dal commercialista un XML di prova per ogni caso (condominio con ritenuta, azienda in inversione contabile, nota di credito). Puoi anche verificare i file con il controllo gratuito del portale.

## Da sapere

- **Piano gratuito di Supabase**: il progetto viene messo in pausa dopo una settimana senza utilizzo e non include backup automatici. Per dati contabili valuta il piano Pro; in ogni caso usa ogni tanto **Esporta dati** come copia di sicurezza.
- **Email di sistema**: il servizio email incluso in Supabase invia pochi messaggi all'ora. Se registri molti dipendenti insieme, alcuni potrebbero dover riprovare più tardi; per un uso intenso si configura un SMTP proprio (Authentication → Emails).
