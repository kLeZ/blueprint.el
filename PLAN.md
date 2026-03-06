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

- ~~PDF, HTML, DOCX (con ox-pandoc)~~

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

- [ ] `blueprint-questions.el`: `blueprint--find-heading` non gestisce heading
      con TODO keyword o tag (`:raw-value` esclude il tag ma
      `re-search-forward "^\\* "` usato subito dopo per trovare il prossimo
      heading può matchare heading nested al livello sbagliato)
- [ ] `blueprint-sync.el`: `blueprint--sync-section` inserisce `\n` prima del
      content dopo il char già presente alla fine del marker, producendo una
      riga vuota extra a ogni sync (cosmetic, non funzionale)
- [x] `blueprint-wizard.el`: `blueprint-wizard-component` popola
      `#+BLUEPRINT_OWNER:` e `#+BLUEPRINT_TECH:` (presenti nel template
      `component.org`) ma nessun altro modulo li leggeva — **fix**: aggiunte
      colonne Owner e Tech alla dashboard (`blueprint-dashboard.el` ora richiede
      `blueprint-c4` e legge i keyword via `blueprint--org-keyword`).
- [x] `blueprint-export.el`: il docstring di `blueprint--master-or-error` diceva
      "creating it if needed" ma la funzione segnala `user-error` senza creare
      nulla. **fix**: docstring corretto; messaggio di errore aggiornato a "run
      blueprint-init or blueprint-sync first".

### 8.2 Miglioramenti ai test

- [ ] Aggiungere test per `blueprint-dashboard.el` (buffer entries, focus mode)
- [ ] Aggiungere test per `blueprint-migrate.el` (diff e migrazione
      non-distruttiva)
- [ ] Aggiungere test per `blueprint-watch.el` (hook install/remove)
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
