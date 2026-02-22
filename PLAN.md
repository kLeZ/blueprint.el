# Blueprint — Piano di implementazione

## Panoramica

25 feature documentate nel README come "Roadmap" sono completamente assenti
dal codice. Questo piano le organizza in 7 fasi ordinate per dipendenze,
partendo dalle fondamenta (infrastruttura e core) fino alle feature più
avanzate (AI, CI).

Ogni fase è autocontenuta: al termine di ciascuna il pacchetto è
funzionante e testabile.

---

## Fase 1 — Fondamenta e infrastruttura core

Obiettivo: rafforzare il core con le utility necessarie a tutte le fasi
successive.

### 1.1 Metrics caching (`blueprint-core.el`)
- Aggiungere una hash-table cache per le metriche dei componenti
- Invalidazione automatica via `after-save-hook` (hash del file)
- Funzione `blueprint--invalidate-cache` e `blueprint--cached-metrics`
- Le funzioni esistenti (`blueprint--component-metrics`,
  `blueprint-health-score`) devono usare la cache

### 1.2 Component CRUD completo (`blueprint-core.el`)
- `blueprint-list-components` — buffer con lista navigabile
- `blueprint-rename-component` — rinomina directory + aggiorna
  BLUEPRINT_DEPENDS in tutti i componenti
- `blueprint-delete-component` — rimuove directory (con conferma)

### 1.3 ADR management (`blueprint-adr.el`) — nuovo file
- `blueprint-adr-new` — crea un nuovo ADR con numerazione automatica
  (0001-title.org, 0002-title.org, …)
- `blueprint-adr-list` — buffer con lista ADR navigabile
- Template ADR (aggiungere `templates/adr.org` con sezioni: Context,
  Decision, Status, Consequences)

### 1.4 Linter (`blueprint-lint.el`) — nuovo file
- `blueprint-lint` — valida tutti i componenti, ritorna lista di warning:
  - Heading Arc42 mancanti (confronto con template)
  - Marker non risolti (QUESTION, TBD, FIXME) oltre soglia
  - BLUEPRINT_DEPENDS che referenzia componenti inesistenti
  - File arc42.org vuoti o con solo heading
- `blueprint-lint-component` — lint su singolo componente
- Output in buffer `*Blueprint Lint*` con `compilation-mode` per
  navigazione
- Exit code non-zero in batch mode per CI

---

## Fase 2 — Dashboard e navigazione

Obiettivo: buffer Magit-style come hub centrale del progetto.

### 2.1 Dashboard buffer (`blueprint-dashboard.el`) — nuovo file
- `blueprint-dashboard` — apre buffer `*Blueprint*` con:
  - Header: nome progetto, health score, data ultimo aggiornamento
  - Sezione componenti: tabella con colonne [Nome | Questions | TBDs |
    FIXMEs | Linee | Stato]
  - Sezione ADR: lista con titolo e stato
  - Navigazione: `RET` apre il file, `g` aggiorna, `q` chiude
- Usa `tabulated-list-mode` come base
- Integra metrics caching dalla Fase 1

### 2.2 Focus mode (parte di `blueprint-dashboard.el`)
- `blueprint-focus` — filtra il dashboard mostrando solo componenti con
  markers aperti (QUESTION/TBD/FIXME > 0)
- Toggle `F` nel dashboard buffer

### 2.3 SVG dashboard (`blueprint-dashboard.el` o file separato)
- `blueprint-dashboard-svg` — genera overview grafica con Graphviz (dot):
  - Nodo per ogni componente, colorato in base al risk score
  - Archi per dipendenze da BLUEPRINT_DEPENDS
  - Legenda colori (verde=ok, giallo=warning, rosso=critical)
- Scrive `dashboard.svg` nella root del progetto

---

## Fase 3 — Gestione contenuti e sync

Obiettivo: strumenti per lavorare sul contenuto dei documenti.

### 3.1 Open questions — AST-based (`blueprint-questions.el`) — nuovo file
- `blueprint-add-question` — inserisce una QUESTION nel heading
  "Open Questions" del componente, usando `org-element` per navigare
  l'AST (niente regex)
- `blueprint-list-questions` — buffer con tutte le domande aperte
  da tutti i componenti, navigabili con RET

### 3.2 Glossary management (`blueprint-glossary.el`) — nuovo file
- Glossario in `.blueprint/glossary.org` con struttura Org:
  ```org
  * Term
  :PROPERTIES:
  :SOURCE: interview-2024-01-15
  :END:
  Definition text.
  ```
- `blueprint-glossary-add` — aggiunge termine (prompt per name,
  definition, source)
- `blueprint-glossary-list` — apre il glossario
- `blueprint-glossary-lookup` — cerca un termine

### 3.3 Reference tracking (`blueprint-references.el`) — nuovo file
- Riferimenti in `.blueprint/references.org` con struttura:
  ```org
  * Reference Title
  :PROPERTIES:
  :TYPE: document|interview|system
  :DATE: 2024-01-15
  :END:
  Notes.
  ```
- `blueprint-reference-add` — aggiunge un riferimento
- `blueprint-reference-list` — apre il buffer riferimenti

### 3.4 Master file sync (`blueprint-sync.el`) — nuovo file
- `blueprint-sync` — sincronizza `master.org` nella root del progetto:
  - Scansiona tutti i componenti
  - Genera/aggiorna direttive `#+INCLUDE:` per ogni componente
  - Non sovrascrive contenuto manuale fuori dalle sezioni auto-generate
  - Sezioni auto-generate delimitate da commenti marker
- Template per master.org (`templates/master.org`)

### 3.5 Ripgrep search (`blueprint-search.el`) — nuovo file
- `blueprint-search` — ricerca project-wide con `rg` (se disponibile,
  fallback a `grep -r`)
- `blueprint-search-questions` — preset: cerca "QUESTION"
- `blueprint-search-tbd` — preset: cerca "TBD"
- `blueprint-search-fixme` — preset: cerca "FIXME"
- Output in buffer `*Blueprint Search*` con `grep-mode`

---

## Fase 4 — Export e automazione

Obiettivo: produrre output e automatizzare workflow ripetitivi.

### 4.1 Org-native export (`blueprint-export.el`) — nuovo file
- `blueprint-export-pdf` — esporta master.org in PDF via Org exporter
  (`org-latex-export-to-pdf`)
- `blueprint-export-docx` — esporta via `ox-pandoc` se disponibile,
  altrimenti errore con messaggio chiaro
- `blueprint-export-html` — esporta in HTML via Org exporter
- Defcustom `blueprint-export-backend` per scegliere il backend default

### 4.2 Async tangle/export (`blueprint-async.el`) — nuovo file
- Wrapper asincrono per operazioni lunghe usando `async.el` o
  `make-thread` (Emacs 29+)
- `blueprint-async-export` — export in background, notifica al termine
- `blueprint-async-tangle` — tangle in background

### 4.3 Auto-tangle on save (hook in `blueprint-core.el`)
- `blueprint-auto-tangle-mode` — minor mode che aggiunge
  `after-save-hook` per eseguire `org-babel-tangle` sui file .org
  dentro `.blueprint/`
- Defcustom `blueprint-auto-tangle` (default nil)

### 4.4 Watch mode (hook in `blueprint-core.el`)
- `blueprint-watch-mode` — minor mode con `after-save-hook` che:
  - Invalida la cache metriche
  - (Opzionale) ri-sincronizza master file
  - (Opzionale) ri-genera C4
- Defcustom `blueprint-watch-auto-sync` (default nil)

---

## Fase 5 — Dependency graph avanzato

Obiettivo: visualizzazione grafica delle dipendenze.

### 5.1 Dependency graph (`blueprint-graph.el`) — nuovo file
- `blueprint-dependency-graph` — genera grafo PlantUML o Graphviz (dot)
  delle dipendenze tra componenti
- Supporta sia PlantUML (`component-deps.puml`) che Graphviz
  (`component-deps.dot`)
- Defcustom `blueprint-graph-backend` ('plantuml o 'graphviz)
- Colorazione nodi basata su health score del componente

---

## Fase 6 — UX e onboarding

Obiettivo: rendere il tool accessibile ai nuovi utenti.

### 6.1 Component skeleton wizard (`blueprint-wizard.el`) — nuovo file
- `blueprint-wizard-component` — wizard interattivo che chiede:
  - Nome componente
  - Responsabilità (una riga)
  - Owner / team
  - Tech stack
  - Dipendenze iniziali
- Pre-compila il template con le risposte

### 6.2 Wizard onboarding (estensione di `blueprint-wizard.el`)
- `blueprint-wizard-init` — guided project setup:
  - Nome progetto
  - Creazione directory
  - Primo componente (opzionale)
  - Migrazione template
  - Apertura dashboard

### 6.3 Quick capture (`blueprint-capture.el`) — nuovo file
- Configura `org-capture-templates` per Blueprint:
  - Nota rapida in `.blueprint/notes.org`
  - Domanda rapida in componente specifico
  - Nuovo termine glossario
- `blueprint-capture` — lancia `org-capture` con i template Blueprint

### 6.4 Daily workflow command (`blueprint-daily.el`) — nuovo file
- `blueprint-daily` — sequenza one-key:
  1. Apre dashboard
  2. Mostra focus mode (componenti da lavorare)
  3. Prompt per selezionare componente
  4. Apre il file
  5. Al salvataggio: sync + export (se watch-mode attivo)

---

## Fase 7 — Intelligence e integrazione esterna

Obiettivo: suggerimenti automatici e integrazioni.

### 7.1 Rule-based risk suggestions (`blueprint-risks.el`) — nuovo file
- Pattern matching deterministico sul testo dei componenti
- Regole predefinite:
  - "single point of failure" → rischio SPOF
  - Nessun owner dichiarato → rischio "unclear ownership"
  - Nessun monitoring menzionato → rischio "missing monitoring"
  - Componente senza dipendenze e non dipeso → rischio "isolated component"
  - Troppi TBD/QUESTION → rischio "immature documentation"
- `blueprint-suggest-risks` — analizza un componente e suggerisce rischi
- `blueprint-suggest-risks-all` — analizza tutto il progetto
- Output nel buffer con possibilità di inserire i rischi nel file

### 7.2 AI-assisted snippets — Ollama (`blueprint-ai.el`) — nuovo file
- Integrazione con Ollama locale (HTTP API su localhost:11434)
- `blueprint-ai-expand` — espande una sezione selezionata (prompt al
  modello con contesto del componente)
- `blueprint-ai-suggest-risks` — suggerisce rischi via LLM (fallback a
  rule-based se Ollama non disponibile)
- `blueprint-ai-boilerplate` — genera boilerplate per sezioni vuote
- Defcustom `blueprint-ai-model` (default "llama3")
- Defcustom `blueprint-ai-endpoint` (default "http://localhost:11434")

### 7.3 Prompt guardrails (parte di `blueprint-ai.el`)
- Context clamping: limita il testo inviato al modello a N caratteri
- Defcustom `blueprint-ai-max-context` (default 4000)
- Sanitizzazione: rimuove dati sensibili (pattern email, IP, password)
  prima di inviare al modello

### 7.4 Org-roam integration (`blueprint-roam.el`) — nuovo file
- Solo se `org-roam` è disponibile (require con soft-dependency)
- Registra i componenti come nodi org-roam
- `blueprint-roam-find` — find-node filtrato su componenti Blueprint
- Backlink navigation tra componenti

### 7.5 CI/headless mode (`blueprint-ci.el`) — nuovo file
- `blueprint-ci-lint` — wrapper batch per linting:
  ```sh
  emacs -Q --batch -l blueprint.el -f blueprint-ci-lint
  ```
- `blueprint-ci-export` — export batch
- `blueprint-ci-validate` — validazione dipendenze + lint + health check
- Exit code appropriati per CI pipeline (0=ok, 1=warning, 2=error)

---

## Aggiornamento Transient menu

Il menu `blueprint-menu` deve essere esteso per esporre tutti i nuovi
comandi. Struttura proposta:

```
Architecture    Quality      Templates   Project
C generate C4   H health     D diff      I init
G dep graph     L lint       M migrate   A add component
                S suggest                R rename
Content         Dashboard                X delete
Q questions     B dashboard  Export      W wizard
Y glossary      F focus      E export
Z references                 T tangle
                Capture
Search          N capture    AI
/ search        . daily      O ai expand
```

---

## File nuovi da creare (14)

1. `blueprint-adr.el`
2. `blueprint-lint.el`
3. `blueprint-dashboard.el`
4. `blueprint-questions.el`
5. `blueprint-glossary.el`
6. `blueprint-references.el`
7. `blueprint-sync.el`
8. `blueprint-search.el`
9. `blueprint-export.el`
10. `blueprint-async.el`
11. `blueprint-graph.el`
12. `blueprint-wizard.el`
13. `blueprint-capture.el`
14. `blueprint-daily.el`
15. `blueprint-risks.el`
16. `blueprint-ai.el`
17. `blueprint-roam.el`
18. `blueprint-ci.el`
19. `templates/adr.org`
20. `templates/master.org`

## File esistenti da modificare

1. `blueprint.el` — require nuovi moduli, estendere transient menu
2. `blueprint-core.el` — metrics caching, component CRUD, minor modes
3. `blueprint-health.el` — usare cache
4. `README.md` — spostare feature da Roadmap a Implemented
