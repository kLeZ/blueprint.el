# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this project is

Blueprint.el is an Emacs Lisp package for text-first architectural assessment
using Org-mode and Arc42 methodology. It generates C4 diagrams (PlantUML) and
dependency graphs (Graphviz), managed through a Transient menu at `C-c b`.

## Commands

### Run tests

```sh
# Full test suite (ERT)
emacs -Q --batch \
  --eval "(push default-directory load-path)" \
  --eval "(push (expand-file-name \"test\" default-directory) load-path)" \
  -l blueprint-core.el -l blueprint-c4.el -l blueprint-health.el \
  -l blueprint-lint.el -l blueprint-adr.el -l blueprint-sync.el \
  -l blueprint-glossary.el -l blueprint-references.el -l blueprint-questions.el \
  -l blueprint-risks.el -l blueprint-ai.el -l blueprint-migrate.el \
  -l blueprint-functional.el -l blueprint-runtime.el \
  -l blueprint-nfr.el -l blueprint-delivery.el -l blueprint-export.el \
  -l blueprint-dashboard.el -l blueprint-watch.el \
  -l test/blueprint-test-helpers.el \
  -l test/blueprint-test-core.el -l test/blueprint-test-health.el \
  -l test/blueprint-test-lint.el -l test/blueprint-test-c4.el \
  -l test/blueprint-test-adr.el -l test/blueprint-test-sync.el \
  -l test/blueprint-test-content.el -l test/blueprint-test-risks.el \
  -l test/blueprint-test-ai.el -l test/blueprint-test-functional.el \
  -l test/blueprint-test-runtime.el \
  -l test/blueprint-test-nfr.el -l test/blueprint-test-delivery.el \
  -l test/blueprint-test-dashboard.el -l test/blueprint-test-migrate.el \
  -l test/blueprint-test-watch.el \
  -l test/blueprint-test-e2e.el -l test/blueprint-test-export.el \
  -f ert-run-tests-batch-and-exit

# Single test by name pattern
emacs -Q --batch \
  --eval "(push default-directory load-path)" \
  --eval "(push (expand-file-name \"test\" default-directory) load-path)" \
  -l blueprint-core.el -l blueprint-health.el \
  -l test/blueprint-test-helpers.el -l test/blueprint-test-health.el \
  --eval "(ert-run-tests-batch \"blueprint-test-health\")"
```

### Lint

```sh
# Byte-compile all files (treats warnings as errors)
emacs -Q --batch \
  --eval "(setq byte-compile-error-on-warn t)" \
  --eval "(push default-directory load-path)" \
  -f batch-byte-compile *.el

# Checkdoc a single file
emacs -Q --batch \
  --eval "(require 'checkdoc)" \
  --eval "(setq checkdoc-force-docstrings-flag nil)" \
  --eval "(with-current-buffer (find-file-noselect \"blueprint-core.el\")
            (let ((warnings (checkdoc-file \"blueprint-core.el\")))
              (when (stringp warnings)
                (message \"%s\" warnings)
                (kill-emacs 1))))"

# Package-lint on entry point only
emacs -Q --batch \
  --eval "(require 'package-lint)" \
  --eval "(push default-directory load-path)" \
  -f package-lint-batch-and-exit blueprint.el
```

### CI headless commands (from `blueprint-ci.el`)

```sh
emacs -Q --batch -l blueprint.el -f blueprint-ci-lint      # exit 0=ok, 1=warning
emacs -Q --batch -l blueprint.el -f blueprint-ci-validate  # exit 0=ok, 1=warn, 2=error
emacs -Q --batch -l blueprint.el -f blueprint-ci-export    # exit 0=ok, 2=error
```

### Releasing

Bump `;;  Version: X.Y.Z` in `blueprint.el` header and push to `main` — the
release workflow creates the git tag and GitHub release automatically.

## Architecture

All modules depend on `blueprint-core.el`, which provides:

- `blueprint--root` — locates `.blueprint/` directory by walking up the tree
- `blueprint--components` — returns a hash table `{name → dir}` of all
  components
- `blueprint--cached-metrics` / `blueprint--invalidate-cache` — MD5-based cache
  for component metrics
- `blueprint--resolve-template` — three-tier template lookup (project → user →
  system)

The entry point `blueprint.el` only wires the Transient menu and `require`s all
modules; no logic lives there.

`blueprint-roam.el` is a soft dependency loaded with
`(require 'blueprint-roam nil t)` in `blueprint.el`.

### Data flow for a typical command

1. Command reads `blueprint--root` to find `.blueprint/`
2. Calls `blueprint--components` to enumerate `arc42.org` files
3. Parses files via `org-element` (never regex on Org content)
4. Uses `blueprint--cached-metrics` to avoid re-reading unchanged files
5. Writes output (`.puml`, `.svg`, buffer) to project root

### Template system (three-tier resolution)

| Priority | Path                             | Purpose                 |
| -------- | -------------------------------- | ----------------------- |
| 1        | `.blueprint/templates/`          | Project-local overrides |
| 2        | `~/.config/blueprint/templates/` | User defaults           |
| 3        | `templates/` in package dir      | System fallback         |

Template files: `component.org`, `adr.org`, `master.org`, `functional.org`,
`infrastructure.org`, `glossary.org`, `references.org`,
`enterprise-context.org`, `enterprise-dependencies.org`, `nfr-quality.org`,
`nfr-constraints.org`, `nfr-risks.org`.

Placeholders: `{{NAME}}` (component name), `{{ID}}` (slugified, for directory
names and PlantUML IDs), `{{PROJECT}}`, `{{AUTHOR}}`, `{{DATE}}`.

**Template provisioning**: When `blueprint-init` is called interactively, it
checks `~/.config/blueprint/templates/`. If any template is missing, it copies
the system templates there and shows a prominent message listing every file
written to the user's home. This ONLY happens interactively (not in batch/tests
— uses `(called-interactively-p 'interactive)`).

### Key Org keyword

`#+BLUEPRINT_DEPENDS: comp1 comp2` in a component's `arc42.org` is the sole
mechanism for declaring inter-component dependencies. C4 diagram generation and
the dependency graph both parse this keyword.

## Code conventions

- All files: `;;; -*- lexical-binding: t; -*-`
- Public symbols: `blueprint-` prefix; private: `blueprint--` (double dash)
- `;;;###autoload` on all interactive public commands
- `defcustom` for all user-facing settings, group `blueprint`
- Parse Org files with `org-element`, never with regex
- Optional integrations: `(require 'feature nil t)`

### Other autoloaded modules

`blueprint.el` also `require`s several single-purpose modules that still have
no dedicated ERT suite and are not part of the test commands above:

- `blueprint-daily.el` — one-key daily triage (dashboard -> focus -> component)
- `blueprint-search.el` — project-wide search via ripgrep, with a fallback
- `blueprint-graph.el` — dependency graphs in PlantUML/Graphviz (dot)
- `blueprint-wizard.el` — interactive onboarding/component-creation wizards
- `blueprint-async.el` — background processing for long-running ops (export, tangle)
- `blueprint-capture.el` — `org-capture` templates for quick notes

Treat diffs touching these as untested until a suite is added.
`blueprint-dashboard.el`, `blueprint-migrate.el`, and `blueprint-watch.el` are
covered (see the Test structure table below).

## Test structure

Tests in `test/` usano ERT. Il macro `blueprint-test--with-project` crea una
directory temporanea con struttura `.blueprint/` e la pulisce dopo ogni test.

| File                           | Scope                                         |
| ------------------------------ | --------------------------------------------- |
| `blueprint-test-helpers.el`    | Macro e utility condivise                     |
| `blueprint-test-core.el`       | Root, cache, CRUD                             |
| `blueprint-test-health.el`     | Metriche e health score                       |
| `blueprint-test-lint.el`       | Linter (incluso fix file mancante)            |
| `blueprint-test-c4.el`         | Keyword extraction, C4 gen                    |
| `blueprint-test-adr.el`        | ADR numerazione e creazione                   |
| `blueprint-test-sync.el`       | Master sync e marker                          |
| `blueprint-test-content.el`    | Glossario, riferimenti, domande               |
| `blueprint-test-risks.el`      | Pattern matching e check strutturali          |
| `blueprint-test-ai.el`         | Sanitizzazione e clamping (no Ollama)         |
| `blueprint-test-functional.el` | Area/feature/entità/integrazione incrementale |
| `blueprint-test-runtime.el`    | Flussi runtime e diagrammi UC/sequenza        |
| `blueprint-test-nfr.el`        | Quality scenarios, vincoli, registro rischi   |
| `blueprint-test-delivery.el`   | Pre-delivery check e master sync              |
| `blueprint-test-dashboard.el`  | Entry, status, focus mode, colonne Owner/Tech |
| `blueprint-test-migrate.el`    | Template diff/migrazione non distruttiva      |
| `blueprint-test-watch.el`      | Minor mode hook install/remove, invalidazione cache |
| `blueprint-test-e2e.el`        | Lifecycle completo di un progetto             |
| `blueprint-test-export.el`     | Titolo duplicato multi-file, config PlantUML headless |

## Blueprint init: full project structure

`blueprint-init` creates more than just `.blueprint/`:

```
.blueprint/
├── components/
├── adr/
├── templates/             # copied from system if absent
├── enterprise/
│   ├── enterprise-context.org
│   └── enterprise-dependencies.org
├── nfr/
│   ├── nfr-quality.org
│   ├── nfr-constraints.org
│   └── nfr-risks.org
├── _archive/
├── glossary.org
└── references.org
master.org                 # six-part assessment deliverable
```

`blueprint-add-component` creates three files per component:

- `arc42.org` — arc42 architectural view
- `functional.org` — technology-agnostic functional spec
- `infrastructure.org` — infrastructure census

Only `arc42.org` is required; the other two are created only when their
templates exist (graceful degradation).

## Master sync: three sections

`blueprint-sync` manages three independent `#+INCLUDE:` sections in
`master.org`:

| Marker pair                                           | File synced          |
| ----------------------------------------------------- | -------------------- |
| `@@blueprint-sync-start@@` / `@@blueprint-sync-end@@` | `arc42.org`          |
| `@@blueprint-sync-functional-start@@` / `-end@@`      | `functional.org`     |
| `@@blueprint-sync-infra-start@@` / `-end@@`           | `infrastructure.org` |

Missing marker pairs are silently skipped (backward compatible).
`blueprint--generate-includes-for` only emits includes for components that
actually have the file (prevents spurious includes for partially migrated
projects).

## Assessment methodology

Templates follow the methodology from
`assessment-framework/methodology/METHOD.org`:

- **Information source hierarchy**: code > tests > logs > monitoring >
  interviews > docs
- **Marking conventions** (Italian, used in templates):
  - `[DA VALIDARE]` — information not yet confirmed
  - `[FINDING]` — confirmed observation
  - `[APPROVATO YYYY-MM-DD]` — stakeholder-approved
  - `[FONTE: X]` — information source attribution
- **Master document structure** (six parts, Italian):
  - Parte 0 — Premesse (methodology, sources, conventions)
  - Parte I — Architettura enterprise (context, dependencies)
  - Parte II — Architettura per componente (arc42, auto-synced)
  - Parte III — Specifiche funzionali (functional, auto-synced)
  - Parte IV — Censimento infrastrutturale (infra, auto-synced)
  - Parte V — Requisiti non funzionali e rischi (NFR, quality)

## Bug noti e fix

- **`blueprint-lint.el`**: `blueprint--lint-component` restituiva lista vuota
  quando `file` era nil o mancante (il `(list ...)` nella branch `then`
  dell'`if` veniva scartato; `(nreverse warnings)` era sempre l'ultima
  espressione). **Fix**: struttura `if` riscritta con l'intera logica nella
  branch `else`.

- **`BLUEPRINT_DEPENDS` regex**: `\\s-*` in Elisp include i newline (tramite la
  syntax class whitespace). In `"^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)"` il
  pattern poteva catturare testo dalla riga successiva (es. `"* Introduction"`),
  causando falsi positivi nel controllo dipendenze isolate. **Fix**: sostituito
  con `[[:blank:]]*` (solo spazi/tab orizzontali) in `blueprint-risks.el`,
  `blueprint-dashboard.el`, `blueprint-ci.el`, `blueprint-lint.el`.

- **`test/blueprint-test-e2e.el`**: parentesi sbilanciata nell'`ert-deftest`
  `multi-component-c4` — mancava un `)` finale. **Fix**: aggiunto `)` alla fine
  della riga 143.

- **ADR — modello single-file**: gli ADR sono ora in un unico file
  `.blueprint/adr/adr.org`. Ogni ADR è un heading di livello 1 con formato
  `* ADR 0001: Titolo` e status nel `:PROPERTIES:` drawer
  (`:STATUS: proposed|accepted|deprecated|superseded`).
  `blueprint--adr-next-number` scansiona i heading in `adr.org` anziché contare
  file. `blueprint-adr-list` usa `org-element-property :STATUS` dal drawer. Il
  vecchio modello (un file per ADR) è stato rimosso completamente.

- **`blueprint-sync.el` — `blueprint--sync-section`**: la ricerca del
  `end-marker` partiva da `(point-min)` invece che dalla posizione corrente
  (dopo il `start-marker`). Se il `end-marker` appariva nel buffer prima del
  `start-marker` (file malformato o marker duplicato), `delete-region` riceveva
  gli argomenti invertiti (`start > end`) e segnalava un errore. **Fix**:
  rimosso `(goto-char (point-min))` prima della ricerca del `end-marker`; la
  ricerca parte ora dalla posizione già avanzata dopo il `start-marker`. Test di
  regressione: `blueprint-test-sync/sync-section-end-must-follow-start`.

- **`blueprint-export.el` — titolo duplicato nell'export multi-file**:
  `#+TITLE` ha comportamento `parse` in `org-export-options-alist` (concatena
  valori multipli). Ogni file satellite incluso in `master.org` via
  `#+INCLUDE` porta il proprio `#+TITLE` (per essere leggibile standalone), e
  org lo mantiene nel buffer espanso: il titolo del documento esportato
  diventava la concatenazione di tutti i titoli inclusi. **Fix**: nuova
  `blueprint--strip-duplicate-titles` agganciata a
  `org-export-before-parsing-functions` al caricamento del pacchetto — rimuove
  ogni `#+TITLE` tranne il primo dopo l'espansione degli `#+INCLUDE` e prima
  che org raccolga le keyword del documento. Essendo una variabile hook
  globale, vale anche per l'export ODT nativo di org (che
  `blueprint-export.el` non gestisce direttamente). Implementata con
  `org-element` (non regex): individua solo i nodi keyword reali, per non
  toccare un `#+TITLE:` mostrato come testo di esempio dentro un blocco
  `example`/`src` (pattern comune nei file org tutorial-style, verificato su
  un config.org reale con blocchi `EXAMPLE`). Test di regressione:
  `test/blueprint-test-export.el`.

- **`blueprint-health.el` — `blueprint--display-marker-list`**:
  `(blueprint--root)` veniva chiamato dentro
  `(with-current-buffer (get-buffer-create bufname) ...)`. Se il buffer esisteva
  già da un test precedente (con `default-directory` di un progetto temporaneo
  già eliminato), `blueprint--root` non trovava `.blueprint/` e la funzione
  falliva. **Fix**: `root` catturato fuori da `with-current-buffer`, prima dello
  switch di buffer. Sintomo: `blueprint-test-list-findings/finds-marker` passava
  in isolamento ma falliva in suite completa.

- **`blueprint-questions.el` — riga vuota persa prima dell'heading successivo**:
  `blueprint-add-question` inserisce la nuova QUESTION alla posizione
  dell'heading successivo (`next-heading`, trovato via
  `re-search-forward "^\\* "`), consumando così la riga vuota che separava la
  sezione "Open Questions" dall'heading successivo. Il presunto bug collegato
  a heading con TODO keyword/tag (`:raw-value` non gestirebbe questi casi) è
  stato verificato come infondato: `:raw-value` esclude già correttamente sia
  il TODO keyword sia i tag. **Fix**: dopo l'insert, se il carattere
  immediatamente successivo è `*` (nessuna riga vuota residua), viene
  reinserita. Test di regressione:
  `blueprint-test-questions/preserves-blank-line-before-next-heading`.

- **`blueprint-export.el` — diagrammi PlantUML persi in silenzio nell'export
  headless**: `emacs -Q --batch` (necessario per CI/riproducibilità) parte
  con `org-confirm-babel-evaluate` a `t` e `org-plantuml-exec-mode` a
  `'jar`; senza disattivare il primo e passare il secondo all'eseguibile,
  ogni blocco `#+begin_src plantuml` viene esportato come listato di
  codice al posto dell'immagine, senza errori né warning — funziona solo
  per caso in sessione interattiva perché l'`init.el` dell'utente già
  imposta questi valori. **Fix**: macro `blueprint--with-plantuml-export`,
  usata da tutte e quattro le funzioni di export; `let`-binding (non
  `setq`) e solo quando la variabile è ancora al default di libreria, così
  non tocca mai una configurazione utente già presente. `ob-plantuml` va
  richiesto a livello di file, non dentro la macro: altrimenti
  `org-plantuml-exec-mode` non è ancora dichiarata "special" quando il
  primo `let` la binda, e si ottiene `void-variable` o
  `"Defining as dynamic an already lexical var"` a runtime. Test di
  regressione: `blueprint-test-export/plantuml-export-*`.

- **`blueprint-sync.el` — riga vuota spuria a ogni sync**:
  `blueprint--sync-section` inseriva `(insert "\n" content "\n")`, ma il punto
  di inserimento (`(1+ start)`) è già a inizio riga subito dopo lo
  start-marker: il `\n` iniziale produceva quindi una riga vuota extra fra
  marker e contenuto sincronizzato a ogni chiamata di `blueprint-sync`.
  **Fix**: rimosso il `\n` iniziale ridondante. Test di regressione:
  `blueprint-test-sync/sync-section-no-spurious-blank-line`.

- **`templates/nfr-risks.org` — riga placeholder**: il template conteneva
  `| R-001 | |...|` come esempio, causando `blueprint--nfr-next-risk-id` →
  `R-002` invece di `R-001` dopo `blueprint-init`. **Fix**: esempio spostato in
  sezione `* Guida… :noexport:` separata; la tabella reale parte vuota. Pattern
  applicato a tutti i template.

- **Template `:noexport:` pattern**: tutti i template ora contengono una sezione
  `* Guida alla compilazione :noexport:` con dati realistici (progetto fittizio
  "PiattaformaPagamenti"). Le sezioni `:noexport:` sono visibili in Emacs e
  nella revisione del file Org grezzo, ma escluse dall'export HTML/PDF. Il
  codice non le raggiunge mai perché cerca heading specifici (es.
  `"* Registro dei rischi"`) che vengono dopo la guida.

## Health scoring

Score starts at 100, deducting per unresolved marker across all component files:

- **Technical markers**: `QUESTION` = −3, `TBD` = −2, `FIXME` = −4
- **Methodology markers**: `[DA VALIDARE]` = −1, `[FINDING]` = −2,
  `[DA REVISIONARE]` = −1

Clamped to 0 minimum. Technical marker results cached by MD5 via
`blueprint--cached-metrics`. Methodology markers counted separately via
`blueprint--methodology-metrics` (not cached — avoids cache key collision with
the existing cache keyed by file path).

`blueprint-list-findings` and `blueprint-list-unvalidated` scan all `.org` files
in the project and display results in a read-only buffer.
`blueprint--display-marker-list` captures `(blueprint--root)` **before**
`(with-current-buffer ...)` to avoid stale `default-directory` from pre-existing
result buffers (isolation-critical for tests).
