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
| `supabase/schema.sql` | Tabelle e permessi del database, da eseguire una volta in Supabase |
| `config.js` | Indirizzo del progetto Supabase e chiave pubblica (anon) |
| `vendor/` | Libreria Supabase (MIT), inclusa per non dipendere da CDN esterni |

## Messa in funzione (una volta sola)

### 1. Database
1. Supabase → **SQL Editor** → **New query**.
2. Incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**.
3. L'ultima riga mostra l'email del titolare (`luciorosalba@gmail.com`). Se vuoi usarne un'altra, cambiala nello script (sezione 1) e rilancialo.

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

## Come funziona

- **Tipi di pagamento e incasso** (Contabilità → Tipi di pagamento): rimessa diretta, bonifico, RiBa, SDD, contanti, assegno, POS, PagoPA e tutti gli strumenti della fattura elettronica (MP01–MP23). Ogni tipo definisce i giorni delle rate, il calcolo da data fattura o fine mese, il giorno fisso, i mesi esclusi, l'IVA alla prima rata e il conto predefinito. Clienti e fornitori hanno il loro tipo; le fatture lo propongono e calcolano le rate, modificabili a mano. Lo **Scadenzario** elenca tutte le rate aperte.

- **Permessi**: il titolare (l'email in `impostazioni`) legge e scrive tutto. Ogni dipendente legge solo la propria agenda e le proprie timbrature, e può solo aggiungere timbrature proprie. Lo impone il database stesso (Row Level Security), non l'app.
- **Agenda dei dipendenti**: il gestionale pubblica per ogni dipendente con email i turni da ieri ai prossimi 14 giorni. Lo rifà ogni volta che cambi turni, sedi o assenze e ogni 15 minuti finché resta aperto. Se nessuno apre il gestionale per più di due settimane, l'agenda dei dipendenti si esaurisce.
- **Timbrature**: l'ora è quella del server, non del telefono. Si possono timbrare solo i turni della propria agenda, e solo il giorno stesso. La fine richiede prima l'inizio. Le correzioni del titolare restano segnate come "corretta".
- **Posizione GPS**: è disattivata finché non la attivi in Impostazioni. In Italia è un controllo a distanza (art. 4 Statuto dei Lavoratori): verifica prima con il consulente del lavoro.

## Da sapere

- **Piano gratuito di Supabase**: il progetto viene messo in pausa dopo una settimana senza utilizzo e non include backup automatici. Per dati contabili valuta il piano Pro; in ogni caso usa ogni tanto **Esporta dati** come copia di sicurezza.
- **Email di sistema**: il servizio email incluso in Supabase invia pochi messaggi all'ora. Se registri molti dipendenti insieme, alcuni potrebbero dover riprovare più tardi; per un uso intenso si configura un SMTP proprio (Authentication → Emails).
- Le fatture sono documenti di gestione interna: l'invio allo SdI va fatto con il programma di fatturazione elettronica.
