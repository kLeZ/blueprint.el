# Blueprint — Piano di implementazione

## Panoramica

Questo file traccia lo stato di implementazione delle feature e raccoglie idee
per lo sviluppo futuro. Le sezioni con ~~testo barrato~~ sono completate.

---

## ~~Fase 1 — Fondamenta e infrastruttura core~~ ✅

### ~~1.1 Metrics caching (`blueprint-core.el`)~~ ✅

- ~~Hash-table cache con invalidazione MD5~~
- ~~`blueprint--invalidate-cache` e `blueprint--cached-metrics`~~

### ~~1.2 Component CRUD completo (`blueprint-core.el`)~~ ✅

- ~~`blueprint-list-components`~~
- ~~`blueprint-rename-component`~~
- ~~`blueprint-delete-component`~~

### ~~1.3 ADR management (`blueprint-adr.el`)~~ ✅

- ~~`blueprint-adr-new` con numerazione automatica~~
- ~~`blueprint-adr-list`~~
- ~~Template `templates/adr.org`~~

### ~~1.4 Linter (`blueprint-lint.el`)~~ ✅

- ~~`blueprint-lint` e `blueprint-lint-component`~~
- ~~Heading check, marker threshold, dangling deps, empty content~~
- ~~**BUGFIX**: `blueprint--lint-component` restituiva lista vuota se il file
  mancava~~

---

## ~~Fase 2 — Dashboard e navigazione~~ ✅

### ~~2.1 Dashboard buffer (`blueprint-dashboard.el`)~~ ✅

- ~~`blueprint-dashboard` con `tabulated-list-mode`~~
- ~~Header con health score e numero componenti~~

### ~~2.2 Focus mode~~ ✅

- ~~`blueprint-focus` — filtra componenti con marker aperti~~

### ~~2.3 SVG dashboard~~ ✅

- ~~`blueprint-dashboard-svg` — Graphviz con colorazione risk-based~~

---

## ~~Fase 3 — Gestione contenuti e sync~~ ✅

### ~~3.1 Open questions — AST-based (`blueprint-questions.el`)~~ ✅

- ~~`blueprint-add-question` via `org-element`~~
- ~~`blueprint-list-questions`~~

### ~~3.2 Glossary management (`blueprint-glossary.el`)~~ ✅

- ~~`blueprint-glossary-add`, `blueprint-glossary-list`,
  `blueprint-glossary-lookup`~~

### ~~3.3 Reference tracking (`blueprint-references.el`)~~ ✅

- ~~`blueprint-reference-add`, `blueprint-reference-list`~~

### ~~3.4 Master file sync (`blueprint-sync.el`)~~ ✅

- ~~`blueprint-sync` con marker `@@blueprint-sync-start@@` /
  `@@blueprint-sync-end@@`~~

### ~~3.5 Ripgrep search (`blueprint-search.el`)~~ ✅

- ~~`blueprint-search`, preset per QUESTION/TBD/FIXME~~

---

## ~~Fase 4 — Export e automazione~~ ✅

### ~~4.1 Org-native export (`blueprint-export.el`)~~ ✅

- ~~PDF, ODT, HTML, DOCX (con ox-pandoc)~~
- ~~`blueprint-export-dispatch`: hand-off al menu standard `org-export-dispatch`
  su master.org, per scegliere backend/template a runtime invece che via
  `blueprint-export-backend` fisso~~
- ~~Default backend resta `pdf` (valore di pacchetto); un utente che preferisce
  `odt` (es. per un template aziendale via `#+ODT_STYLES_FILE:`, che il PDF
  via LaTeX non applica) lo imposta nella propria config (`:custom` nel
  `use-package blueprint`), non nel pacchetto~~

### ~~4.2 Async tangle/export (`blueprint-async.el`)~~ ✅

- ~~`blueprint-async-export`, `blueprint-async-tangle` via `make-thread`~~

### ~~4.3 Auto-tangle on save~~ ✅

- ~~`blueprint-auto-tangle-mode` minor mode~~

### ~~4.4 Watch mode~~ ✅

- ~~`blueprint-watch-mode` con auto-sync e auto-C4~~

---

## ~~Fase 5 — Dependency graph avanzato~~ ✅

### ~~5.1 Dependency graph (`blueprint-graph.el`)~~ ✅

- ~~PlantUML e Graphviz, colorazione health-based~~

---

## ~~Fase 6 — UX e onboarding~~ ✅

### ~~6.1 Component skeleton wizard (`blueprint-wizard.el`)~~ ✅

- ~~`blueprint-wizard-component` con pre-compilazione~~

### ~~6.2 Wizard onboarding~~ ✅

- ~~`blueprint-wizard-init`~~

### ~~6.3 Quick capture (`blueprint-capture.el`)~~ ✅

- ~~Template org-capture per note, domande, glossario~~

### ~~6.4 Daily workflow command (`blueprint-daily.el`)~~ ✅

- ~~`blueprint-daily` — sequenza triage giornaliero~~

---

## ~~Fase 7 — Intelligence e integrazione esterna~~ ✅

### ~~7.1 Rule-based risk suggestions (`blueprint-risks.el`)~~ ✅

- ~~Pattern matching deterministico + check strutturali~~

### ~~7.2 AI-assisted snippets — Ollama (`blueprint-ai.el`)~~ ✅

- ~~`blueprint-ai-expand`, `blueprint-ai-suggest-risks`,
  `blueprint-ai-boilerplate`~~

### ~~7.3 Prompt guardrails~~ ✅

- ~~Context clamping + sanitizzazione email/IP/password~~

### ~~7.4 Org-roam integration (`blueprint-roam.el`)~~ ✅

- ~~Soft dependency con `require ... nil t`~~

### ~~7.5 CI/headless mode (`blueprint-ci.el`)~~ ✅

- ~~`blueprint-ci-lint`, `blueprint-ci-export`, `blueprint-ci-validate`~~

---

## ~~Infrastruttura test e licenza~~ ✅

- ~~Suite ERT in `test/` a più livelli (unit, integration, end-to-end)~~
- ~~CI GitHub Actions (`test.yml`) che esegue tutti i test~~
- ~~Licenza MIT (`LICENSE`)~~
- ~~`AGENTS.md` per agenti AI~~
- ~~Fix bug `blueprint--lint-component` (file mancante silenzioso)~~

---

## Fase 8 — Qualità e robustezza (TODO)

### 8.1 Fix noti e tech debt

- [x] `blueprint-questions.el`: investigato il presunto bug di
      `blueprint--find-heading` con heading a TODO keyword/tag — verificato
      via probe diretto su `org-element-parse-buffer` che `:raw-value` esclude
      correttamente sia il TODO keyword sia i tag, quindi il matching
      dell'heading funziona già bene in quel caso. Trovato invece un bug reale
      e indipendente dal TODO/tag in `blueprint-add-question`: quando esiste
      già un heading successivo, l'inserimento della nuova QUESTION consuma la
      riga vuota che separava la sezione "Open Questions" dall'heading
      successivo, incollandoli. **fix**: dopo l'insert, se il carattere
      immediatamente successivo è `*` (heading senza riga vuota), viene
      reinserita la riga vuota. Test di regressione:
      `blueprint-test-questions/preserves-blank-line-before-next-heading`.
- [x] `blueprint-sync.el`: `blueprint--sync-section` inseriva `\n` prima del
      content anche se `(1+ start)` è già posizionato a inizio riga subito
      dopo lo start-marker, producendo una riga vuota extra a ogni sync
      (cosmetic, non funzionale). **fix**: rimosso il `\n` iniziale ridondante
      da `(insert "\n" content "\n")` → `(insert content "\n")`. Test di
      regressione: `blueprint-test-sync/sync-section-no-spurious-blank-line`.
- [x] `blueprint-wizard.el`: `blueprint-wizard-component` popola
      `#+BLUEPRINT_OWNER:` e `#+BLUEPRINT_TECH:` (presenti nel template
      `component.org`) ma nessun altro modulo li leggeva — **fix**: aggiunte
      colonne Owner e Tech alla dashboard (`blueprint-dashboard.el` ora richiede
      `blueprint-c4` e legge i keyword via `blueprint--org-keyword`).
- [x] `blueprint-export.el`: il docstring di `blueprint--master-or-error` diceva
      "creating it if needed" ma la funzione segnala `user-error` senza creare
      nulla. **fix**: docstring corretto; messaggio di errore aggiornato a "run
      blueprint-init or blueprint-sync first".
- [x] `blueprint-export.el`: `#+TITLE` è una keyword "cumulativa" per
      org-export (`parse` behaviour in `org-export-options-alist`, concatena
      valori multipli). Ogni file satellite incluso in `master.org` via
      `#+INCLUDE` porta il proprio `#+TITLE` (utile per editing standalone), e
      org lo mantiene nel buffer espanso: il titolo del documento esportato
      (ODT/PDF/HTML/DOCX) diventava la concatenazione di tutti i titoli inclusi
      invece del solo titolo del master. Rilevato su un progetto reale
      (progetto pilota, 17 file satellite inclusi). **fix**: nuova
      `blueprint--strip-duplicate-titles`, agganciata a
      `org-export-before-parsing-functions` al caricamento del pacchetto —
      gira dopo l'espansione degli `#+INCLUDE` e prima che org raccolga le
      keyword del documento, rimuove ogni `#+TITLE` tranne il primo. Vale per
      qualunque backend e per l'export ODT nativo di org (non gestito da
      `blueprint-export.el`), perché agisce su una variabile hook globale.
      Implementata con `org-element` (non regex): individua solo i nodi
      keyword reali, così un `#+TITLE:` mostrato come testo di esempio dentro
      un blocco `example`/`src` (pattern comune nei file org tutorial-style)
      resta intatto. Test di regressione: `test/blueprint-test-export.el`.
- [ ] `#+ODT_STYLES_FILE` con un template aziendale "grezzo" (un `.ott`
      scritto in Writer, non derivato dall'export di org) produce un export
      ODT rotto **senza alcun errore o warning**: quel file sostituisce
      integralmente `styles.xml`, che di norma contiene anche gli stili
      interni di cui org ha bisogno (`OrgDisplayImage`, `OrgTable*`,
      `OrgCode`, `OrgBulletedList`/`OrgNumberedList`, ecc. — verificati 13+
      nomi diversi in un caso reale). Un template aziendale normale non li
      conosce: il documento risulta "quasi giusto" (gli stili standard come
      Heading/Text body hanno un fallback implicito in LibreOffice) ma le
      immagini a paragrafo (ogni diagramma PlantUML incluso via
      `#+begin_src plantuml :file x.svg`) si sovrappongono al contenuto
      successivo invece di riservare lo spazio verticale, perché
      `OrgDisplayImage` — che imposta `wrap="none"` — non esiste da nessuna
      parte. Rilevato su un progetto reale (progetto pilota,
      `template-aziendale.ott`), segnalato dall'utente come "problema col
      documento finale" senza altro contesto: diagnosticato confrontando
      ogni `style-name` referenziato in `content.xml` con quelli definiti in
      `content.xml`+`styles.xml` esportati. Fix applicato manualmente in
      quel progetto (unione degli stili mancanti, presi da
      `OrgOdtStyles.xml`, dentro lo `styles.xml` del template aziendale) ma
      **nel pacchetto manca tuttora qualunque controllo**: proposta —
      un check in `blueprint-ci-validate` (o funzione dedicata) che, dato un
      `#+ODT_STYLES_FILE`, estragga gli stili referenziati da un export di
      prova e segnali quelli assenti dal file styles.xml risultante, prima
      che l'utente scopra il difetto solo aprendo il documento finale.
- [x] L'export via `emacs -Q --batch` (necessario per riproducibilità/CI,
      fuori dalla sessione Emacs interattiva dell'utente) **perdeva in
      silenzio tutti i diagrammi PlantUML** senza impostare esplicitamente
      `org-confirm-babel-evaluate` (nil), `org-plantuml-exec-mode`
      (`'plantuml`, eseguibile invece del jar) e `org-babel-do-load-languages`
      con `(plantuml . t)`: senza questi, ogni blocco `#+begin_src plantuml`
      veniva esportato come listato di codice sorgente al posto
      dell'immagine, senza errori né warning. Il problema non è specifico di
      ODT: riguarda ogni backend che passa dal meccanismo Babel-in-export di
      Org (PDF, HTML, DOCX inclusi). **fix**: nuova macro
      `blueprint--with-plantuml-export` in `blueprint-export.el`, usata da
      tutte e quattro le funzioni di export (`blueprint-export-pdf/-odt/-html/
      -docx`). Imposta i tre valori solo per la durata della chiamata di
      export (`let`, non `setq`) e solo se la variabile è ancora al suo
      default di libreria (`org-confirm-babel-evaluate` = `t`,
      `org-plantuml-exec-mode` = `'jar`): una configurazione già presente
      nell'`init.el` dell'utente non viene mai toccata. `ob-plantuml` è ora
      richiesto a livello di file (non dentro la macro) perché altrimenti
      `org-plantuml-exec-mode` non è ancora dichiarata "special" quando un
      `let` prova a bindarla, con conseguente `void-variable` o
      `"Defining as dynamic an already lexical var"` a runtime (lexical
      binding). Test di regressione: `blueprint-test-export/plantuml-export-*`
      in `test/blueprint-test-export.el`.

### 8.2 Miglioramenti ai test

- [x] Aggiungere test per `blueprint-dashboard.el` (buffer entries, focus
      mode, colonne Owner/Tech, status classification) —
      `test/blueprint-test-dashboard.el`
- [x] Aggiungere test per `blueprint-migrate.el` (diff e migrazione
      non-distruttiva) — `test/blueprint-test-migrate.el`. Nota: il test del
      diff deve neutralizzare `kill-buffer-query-functions` prima di ripulire
      il buffer `*diff*`, perché `blueprint-template-diff` lancia `diff` come
      sottoprocesso asincrono via `compilation-start` e altrimenti
      `kill-buffer` chiede conferma leggendo da stdin, che in `--batch`
      fallisce con `end-of-file`.
- [x] Aggiungere test per `blueprint-watch.el` (hook install/remove,
      `blueprint--in-project-p`, invalidazione cache) —
      `test/blueprint-test-watch.el`
- [ ] Test negativi più sistematici (input invalido, file corrotti)

---

## ~~Fase 9.0 — Analisi funzionale incrementale~~ ✅

### ~~9.0 Comandi per costruire functional.org pezzo per pezzo (`blueprint-functional.el`)~~ ✅

Per componenti grandi (monoliti, servizi complessi) il template `functional.org`
vuoto è sovradimensionato: l'utente deve riempire decine di sezioni in una volta
sola. Il nuovo modulo `blueprint-functional.el` offre tre comandi per aggiungere
i singoli blocchi atomici uno alla volta:

- ~~`blueprint-functional-add-area`~~ — heading livello 2 sotto
  `* Aree funzionali` con ancora org `<<comp-area-slug>>` e placeholder
  `[DA VALIDARE]`
- ~~`blueprint-functional-add-feature`~~ — heading livello 3 sotto un'area
  esistente con skeleton completo: Scopo, Input, Output, Regole di business,
  Regole di validazione, Casi limite e eccezioni
- ~~`blueprint-functional-add-entity`~~ — heading livello 2 sotto
  `* Entità di dominio` con tabella attributi e `*** Rappresentazione logica`
- ~~`blueprint-functional-add-integration`~~ — heading livello 2 sotto
  `* Punti di integrazione` con tabella metadati (direzione, controparte,
  protocollo, autenticazione, frequenza, SLA) e `*** Formato scambio` con blocco
  codice per payload/file di scambio

I tre comandi sono esposti nel menu Transient come terza riga **Functional** con
i tasti `a`, `f`, `e`. Il `blueprint-command-map` è aggiornato di conseguenza.

**Tecnica di inserimento**: stessa strategia ibrida di `blueprint-questions.el`
— `org-element` per trovare il heading (`:contents-begin`), poi
`re-search-forward "^\\*{1,N} "` per localizzare il prossimo heading fratello o
superiore, inserimento prima di esso (o a EOF). Le sezioni mancanti
(`* Aree funzionali`, `* Entità di dominio`) vengono create automaticamente se
assenti.

---

## Fase 9 — Nuove feature (idee)

### 9.1 Changelog automatico

Generare un file `CHANGELOG.org` a partire dai messaggi dei commit git e dagli
ADR. Comando: `blueprint-changelog-generate`.

### 9.2 Status tracking per componenti

Aggiungere keyword `#+BLUEPRINT_STATUS: draft|active|deprecated|archived`
interpretata dalla dashboard con icone colorate. Il linter potrebbe avvisare se
un componente `active` ha FIXMEs o dipende da uno `deprecated`.

### 9.3 Metriche trend nel tempo

Registrare lo stato delle metriche (score, conteggi) in
`.blueprint/metrics-history.org` ad ogni sync, in modo da mostrare un grafico
dell'evoluzione del progetto.

### 9.4 Esportazione JSON/YAML per CI

Aggiungere `blueprint-ci-export-json` che produce un file
`blueprint-report.json` con health score, componenti, dipendenze e warning —
utile per integrazione con tool di CI che non supportano Emacs.

### 9.5 Template "enterprise" con multi-livello

Supporto per template `arc42-enterprise.org` con sezioni aggiuntive (enterprise
context, stakeholder map, compliance) per engagement più grandi. L'assessment
framework in `assessment-framework/` contiene già la base.

### 9.6 Integrazione con org-agenda

Convertire le QUESTION e FIXME aperte in task org-agenda con scadenza, in modo
da poter fare triage dal buffer agenda standard di Emacs.

### 9.7 Diff tra versioni di componente

Usare git per mostrare la diff delle modifiche ai file arc42.org con contesto
semantico (quale heading è cambiato, quante domande sono state risolte).
Comando: `blueprint-component-diff`.

### 9.8 Ricerca semantica con org-roam-db

Se org-roam è disponibile, sfruttare il suo database SQLite per ricerche
semantiche tra componenti (componenti simili, cluster di dipendenze, ecc.).

### 9.9 Blueprint per monorepo

Supporto per progetti con più sotto-sistemi: `.blueprint/systems/` con una
directory per sistema, ciascuna con la propria struttura components/adr. Il
dashboard mostrerebbe una vista aggregata multi-sistema.

### 9.10 Live preview nella sidebar

Minor mode che apre un buffer laterale con l'anteprima SVG del grafico delle
dipendenze, aggiornata in tempo reale al salvataggio dei file.

### 9.11 Milestone/cronoprogramma nella dashboard

Trovato pilotando il pacchetto sul progetto pilota: la dashboard
(`blueprint-dashboard.el`) ha solo metriche per componente (Questions/TBD/
FIXME/Status); non esiste alcun concetto di scadenza o milestone a livello
di progetto. Un progetto reale ha quasi sempre un cronoprogramma con
consegne parziali, e sapere "quanto manca alla prossima" è informazione
che vale la pena avere a colpo d'occhio quanto l'health score.

Proposta minimale: per convenzione, se esistono `CRONOPROGRAMMA.org` e/o
`TODO.org` nella root del progetto, `blueprint-dashboard-refresh` aggiunge
alla header-line la prossima milestone aperta (prima riga con keyword
`TODO`/non completata sotto un heading o tabella riconosciuta come
milestone) e il conteggio degli item `TODO` aperti nel progetto. Nessun
nuovo formato da imporre: si riusa Org standard (keyword TODO/DONE,
tabelle) già presente nei progetti pilota. Non implementato: da valutare
se vale la generalizzazione o resta specifico del progetto pilota.

### 9.12 Evoluzione del meccanismo Open Questions (`blueprint-questions.el`)

Trovato progettando una skill di tracking domande sul progetto
pilota. `blueprint-add-question`/`blueprint-list-questions` gestiscono
solo una lista piatta (`- QUESTION <testo>`) per componente: nessun
tag/area, nessuna cronologia di risoluzione (chi ha risposto, quando,
con quale fonte), nessun modo di marcare una domanda come chiusa senza
cancellarla (perderebbe la storia). Il progetto pilota ha dovuto
costruire una sovrastruttura esterna (`DOMANDE.org`, con tag di area e
proiezione selettiva verso `QUESTION` per le domande con un componente
di casa) perché il meccanismo nativo non basta a un assessment con
molte domande cross-componente e con interviste diluite nel tempo.

Proposta (non specificata in dettaglio, da validare se generalizzabile):
- Estendere la riga `QUESTION` con proprietà opzionali (tag/area,
  stato `OPEN`/`ANSWERED`, riferimento alla fonte della risposta),
  mantenendo la sintassi retrocompatibile per chi usa solo il flusso
  attuale.
- `blueprint-list-questions` con filtro per tag/stato, non solo elenco
  piatto.
- Valutare se ha senso un concetto di domanda "senza componente" (oggi
  `blueprint-add-question` richiede sempre un componente).

### 9.13 `blueprint-delete-component` non ripulisce i riferimenti esterni

Trovato rimodulando il perimetro del progetto pilota (un
componente contrattuale è stato ridimensionato ad area
funzionale di un altro componente e va rimosso come componente
blueprint). `blueprint-delete-component` (`blueprint-core.el`) cancella
solo la directory del componente: non tocca le righe `#+INCLUDE` che lo
referenziano in `master.org` (tre, una per arc42/functional/
infrastructure), non aggiorna `BLUEPRINT_DEPENDS` negli altri componenti
che lo citassero, e non rimuove i mirror `QUESTION` residui altrove.
Usarla oggi lascerebbe `master.org` con `#+INCLUDE` verso file
inesistenti (errore di export silenzioso o rumoroso a seconda del
backend). Nel progetto pilota si è scelto di non usarla e di lasciare il
componente fisicamente presente finché il contenuto non viene fuso a
mano nel componente di destinazione (vedi ADR 0005 del progetto).

Proposta (non specificata in dettaglio): `blueprint-delete-component`
dovrebbe, prima di cancellare la directory, cercare e rimuovere le righe
`#+INCLUDE` che puntano al componente in `master.org` (dentro le sezioni
`@@blueprint-sync-*-start/end@@`, coerentemente con come `blueprint-sync`
le gestisce) e segnalare (non rimuovere automaticamente, serve giudizio
umano) le occorrenze del nome componente in `BLUEPRINT_DEPENDS` altrove
nel progetto.

### ~~9.14 Le sezioni sync-managed di `master.org` non separano i componenti con un titolo~~ ✅

Trovato rileggendo l'export finale del progetto pilota: le
tre sezioni gestite da `blueprint-sync` (Parte II arc42, Parte III
functional, Parte IV infrastructure) generavano solo una lista piatta
di `#+INCLUDE` (`blueprint--generate-includes-for`), senza alcun
headline che nominasse il componente prima di ciascun file incluso. Nel
documento esportato, ogni componente iniziava con `* Introduction` (o
un altro headline generico riusato da tutti i componenti): non c'era
modo per il lettore di sapere da un headline che si era passati da un
componente al successivo -- l'unico segnale era la riga `#+TITLE:` del
file incluso, che però org non renderizza mai come separatore a metà
documento (le concatena tutte in un titolo unico, comportamento
*diverso* ma altrettanto inutile a questo scopo). Non era un problema
di export: era strutturale, presente probabilmente fin dalla prima
generazione di `master.org` per qualunque progetto blueprint.el con più
di un componente. Un primo workaround manuale nel progetto pilota
(headline scritti a mano tra i marker sync) si è rivelato fragile: un
resync dopo l'aggiunta/rimozione di un componente cancellava gli
headline aggiunti a mano.

Risolto in `blueprint-sync.el`: `blueprint--generate-includes-for` ora
genera, per ciascun componente, un headline di livello 2 (`**
<NomeComponente>`) subito prima del relativo `#+INCLUDE`, con
`:minlevel 3` invece di 2 perché l'include si annidi correttamente
sotto quel headline. Il nome mostrato viene da una nuova funzione,
`blueprint--component-display-name`, che legge il `#+TITLE:` del file
incluso e ne prende il testo prima del primo `" -- "` (la convenzione
già usata dai template dei componenti, es. "Portale -- Architettura
(arc42)"); se il file non è leggibile o il titolo non segue quella
convenzione, usa il titolo per intero o, in ultima istanza, il nome del
componente capitalizzato. Tre nuovi test in `blueprint-test-sync.el`
coprono l'headline generato, l'estrazione dal `#+TITLE:` e il fallback;
aggiornati i due test esistenti che assumevano `:minlevel 2` e un solo
match di riga per componente. Nessuna migrazione richiesta per i
progetti pilota esistenti: il prossimo `blueprint-sync` rigenera la
sezione con gli headline corretti automaticamente.

---

## Fase 10 — Allineamento metodologico (gap assessment-framework)

Analisi del gap tra la metodologia definita in `assessment-framework/` e le
capacità attuali di Blueprint.el. Le voci sono ordinate per priorità.

### ~~10.1 Comandi interattivi per NFR (PRIORITÀ ALTA)~~ ✅

- ~~`blueprint-nfr-add-quality-scenario` (C-c b p)~~
- ~~`blueprint-nfr-add-constraint` (C-c b c)~~
- ~~`blueprint-nfr-add-risk` con livello calcolato e ID auto-incrementale (C-c b
  t)~~
- ~~Riga "NFR" nel menu Transient~~
- ~~Modulo `blueprint-nfr.el`~~

### ~~10.2 Tracciamento marcature metodologiche (PRIORITÀ ALTA)~~ ✅

- ~~`blueprint--methodology-metrics` — conteggia `[DA VALIDARE]`, `[FINDING]`,
  `[DA REVISIONARE]`~~
- ~~`blueprint-health-score` aggiornato con penalità: -1/+[DA VALIDARE],
  -2/[FINDING], -1/[DA REVISIONARE]~~
- ~~`blueprint-list-findings` (C-c b d)~~
- ~~`blueprint-list-unvalidated` (C-c b g)~~

### ~~10.3 Checklist pre-consegna automatizzata (PRIORITÀ ALTA)~~ ✅

- ~~`blueprint-pre-delivery-check` (C-c b u)~~
- ~~Verifica: health score, [DA VALIDARE], [DA REVISIONARE], lint, master sync~~
- ~~Report in buffer dedicato con badge OK/ATTENZIONE~~

### 10.4 Vista enterprise auto-generata (PRIORITÀ MEDIA)

`blueprint-generate-c4` produce un diagramma Container (C4 L2). La metodologia
prevede anche un diagramma C4 L1 enterprise che mostra tutti i sistemi nel
perimetro e le loro relazioni di alto livello.

- [ ] `blueprint-generate-enterprise-c4` — genera
      `enterprise/enterprise-context.org` con un C4 L1 usando i componenti come
      `System(...)` e le dipendenze come `Rel(...)` (più semplice di C4 L2:
      nessun Container, solo System)
- [ ] Aggiornamento del template `enterprise-context.org` per includere ancora
      org che il comando possa aggiornare

### 10.5 Template activity diagram e DFD (PRIORITÀ MEDIA)

La metodologia prevede esplicitamente:

- UML activity diagram con swimlane per processi di business multi-attore
- DFD (Data Flow Diagram Yourdon/DeMarco) per data lineage e integrazioni

Non esistono sezioni nei template correnti per questi diagrammi.

- [ ] Aggiungere sezione `* Processi di business` a `component.org` con blocco
      PlantUML swimlane template
- [ ] Aggiungere sezione `* Flussi dati` a `functional.org` con blocco PlantUML
      component diagram (simulazione DFD)
- [ ] `blueprint-functional-add-process` — aggiunge un processo di business con
      swimlane template (analogo a `blueprint-runtime-add-flow`)

### 10.6 Differenziazione tipo riferimenti (PRIORITÀ BASSA)

Il `master.org` distingue logicamente riferimenti-documenti da
riferimenti-interviste (ancore `references-interviews`, `references-documents`).
`blueprint-reference-add` usa un tipo libero non strutturato.

- [ ] Aggiungere sezioni separate in `references.org`:
  - `* Interviste` per fonti tipo `interview`
  - `* Documenti` per fonti tipo `document`, `codebase`, `ticket`, `monitoring`
- [ ] `blueprint-reference-add` ordina automaticamente per tipo nella sezione
      corretta

### 10.7 Gestione perimetro (inclusi/esclusi) (PRIORITÀ BASSA)

Non esiste un modo strutturato per marcare componenti come "fuori perimetro con
motivazione". Attualmente va documentato solo nel testo della Parte 0.

- [ ] Keyword `#+BLUEPRINT_STATUS: in-scope|out-of-scope|tbd` in `arc42.org`
- [ ] `blueprint-lint` avvisa se un componente `in-scope` dipende da uno
      `out-of-scope`
- [ ] Dashboard mostra colonna Status con filtro per componenti fuori perimetro
