# AGENTS.md

This file provides guidance to coding agents (Claude Code, opencode and other
AGENTS.md-aware tools) when working with code in this repository.
`CLAUDE.md` only imports this file (`@AGENTS.md`): edit this one.

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
  -l blueprint-dashboard.el -l blueprint-watch.el -l blueprint-capture.el \
  -l test/blueprint-test-helpers.el \
  -l test/blueprint-test-core.el -l test/blueprint-test-health.el \
  -l test/blueprint-test-lint.el -l test/blueprint-test-c4.el \
  -l test/blueprint-test-adr.el -l test/blueprint-test-sync.el \
  -l test/blueprint-test-content.el -l test/blueprint-test-risks.el \
  -l test/blueprint-test-ai.el -l test/blueprint-test-functional.el \
  -l test/blueprint-test-runtime.el \
  -l test/blueprint-test-nfr.el -l test/blueprint-test-delivery.el \
  -l test/blueprint-test-dashboard.el -l test/blueprint-test-migrate.el \
  -l test/blueprint-test-watch.el -l test/blueprint-test-capture.el \
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

- `blueprint--root` — walks up the tree to the nearest directory holding the
  data directory: `blueprint-directory-name` (defcustom, default
  `.blueprint`, may be a nested relative path) or the legacy `.blueprint`
  (fallback, warned once per root per session)
- `blueprint--data-dir` / `blueprint--data-path` — the data directory
  actually in use and paths inside it. Never hardcode `".blueprint"`:
  always go through these (sync writes `#+INCLUDE` paths relative to
  `master.org` for the same reason)
- `blueprint--org-file-regexp` — filter for `directory-files-recursively`
  over Org files; excludes Emacs lock files (`.#x.org`, dangling symlinks)
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

### Key Org keywords

`#+BLUEPRINT_DEPENDS: comp1 comp2` in a component's `arc42.org` is the sole
mechanism for declaring inter-component dependencies. C4 diagram generation and
the dependency graph both parse this keyword.

`#+BLUEPRINT_STATUS: in-scope|out-of-scope|tbd` (default `in-scope` when
absent or unrecognized, via `blueprint--component-scope-status` in
`blueprint-c4.el`) marks a component's assessment perimeter status.
`blueprint-lint` warns when an in-scope component depends on an
out-of-scope one; the dashboard's Scope column and out-of-scope filter
(`blueprint-out-of-scope-view`, or `O` inside the dashboard buffer) read
the same keyword.

## Code conventions

- All files: `;;; -*- lexical-binding: t; -*-`
- Public symbols: `blueprint-` prefix; private: `blueprint--` (double dash)
- `;;;###autoload` on all interactive public commands
- `defcustom` for all user-facing settings, group `blueprint`
- Parse Org files with `org-element`, never with regex
- Optional integrations: `(require 'feature nil t)`
- New documentation and project files are Org (`.org`), e.g. ADRs in
  `docs/adr/`, `CONTEXT.org`. The only Markdown exceptions are `AGENTS.md`
  (required by the tools that read it) and `CLAUDE.md`, which imports it

### Other autoloaded modules

`blueprint.el` also `require`s several single-purpose modules that still have
no dedicated ERT suite and are not part of the test commands above:

- `blueprint-daily.el` — one-key daily triage (dashboard -> focus -> component)
- `blueprint-search.el` — project-wide search via ripgrep, with a fallback
- `blueprint-graph.el` — dependency graphs in PlantUML/Graphviz (dot)
- `blueprint-wizard.el` — interactive onboarding/component-creation wizards
- `blueprint-async.el` — background processing for long-running ops (export, tangle)

Treat diffs touching these as untested until a suite is added.
`blueprint-dashboard.el`, `blueprint-migrate.el`, `blueprint-watch.el`, and
`blueprint-capture.el` (one regression test, not full coverage) are covered
(see the Test structure table below).

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
| `blueprint-test-migrate.el`    | Template diff/migrazione non distruttiva, rename directory dati |
| `blueprint-test-watch.el`      | Minor mode hook install/remove, invalidazione cache |
| `blueprint-test-capture.el`    | Target del template org-capture glossario (regression, non full coverage) |
| `blueprint-test-e2e.el`        | Lifecycle completo di un progetto             |
| `blueprint-test-export.el`     | Titolo duplicato multi-file, config PlantUML headless, check stili ODT, didascalie dei diagrammi |

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

## ODT styles check

`blueprint-check-odt-styles` (`blueprint-export.el`) exports master.org to
ODT, then diffs every style `content.xml` references against what
`#+ODT_STYLES_FILE:` (styles.xml) and content.xml's own automatic-styles
define. Only a style also present in the bundled `OrgOdtStyles.xml`
(`org-odt-styles-dir`) is reported, to avoid false positives from
references that have no explicit definition even in a stock export (e.g.
`Sect1`, part of Org's own table-of-contents scaffolding). The pure
computation lives in `blueprint--check-odt-styles-missing` (no
message/buffer/`kill-emacs`); `blueprint-check-odt-styles` (interactive
buffer) and `blueprint-ci-check-odt-styles` (`blueprint-ci.el`, batch exit
code) both build on it, the same split as `blueprint--lint-component` vs.
`blueprint-lint`/`blueprint-ci-lint`. Requires `unzip`. Not part of
`blueprint-ci-validate`: opt-in, since it needs a real ODT export and only
applies to a project with a corporate `#+ODT_STYLES_FILE:`.

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

- **`blueprint-core.el` — `blueprint-add-component` sovrascriveva un
  componente esistente in silenzio**: `(make-directory dir t)` non segnala
  errore se `dir` esiste già (il flag `PARENTS` sopprime quel controllo).
  Aggiungere un componente il cui id slugificato collide con uno esistente
  (stesso nome digitato due volte, o due nomi che slugificano allo stesso
  id, es. "Order Service" e "order-service") sovrascriveva quindi
  arc42.org/functional.org/infrastructure.org tornando al template vuoto
  — nessun errore, nessuna conferma, nessun modo di recuperare il
  contenuto perso. **Fix**: `user-error` se l'id esiste già in
  `blueprint--components`, prima di creare qualunque file. Test di
  regressione: `blueprint-test-add-component/duplicate-name-errors`,
  `blueprint-test-add-component/slugify-collision-errors`.

- **Lock file di Emacs nelle scansioni ricorsive**: `.#file.org` (symlink
  pendente creato mentre `file.org` ha modifiche non salvate) passava il
  filtro `"\\.org\\'"`; `blueprint-list-findings`/`blueprint-list-unvalidated`
  fallivano con `file-missing`. **Fix**: `blueprint--org-file-regexp`
  (`blueprint-core.el`) in health, async e migrate. Test di regressione:
  `blueprint-test-list-findings/ignores-lock-files`.

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
  **Fix incompleto, poi sostituito**: `blueprint--org-keyword` (c4) aveva
  ancora `\\s-*` (un `#+BLUEPRINT_DEPENDS:` vuoto restituiva
  `"#+BLUEPRINT_OWNER:"`, finito come dipendenza nel C4 e come Owner nella
  dashboard), e la versione `[[:blank:]]*` saltava la riga vuota e
  catturava l'esempio `#+BLUEPRINT_DEPENDS: order-service
  notification-service` dentro il `#+BEGIN_SRC org` della guida
  `:noexport:` del template: ogni componente nuovo "dipendeva" da due
  componenti inesistenti e `blueprint-ci-validate` falliva su ogni
  progetto nuovo. **Fix definitivo**: `blueprint--org-keyword` spostata in
  `blueprint-core.el` e riscritta con `org-element` (valore vuoto = nil,
  keyword dentro blocchi ignorate); lint, ci, dashboard e risks la usano
  al posto delle regex. Test di regressione:
  `blueprint-test-org-keyword/empty-does-not-read-next-line`,
  `.../ignores-src-block-examples`, `.../fresh-component-has-no-deps`,
  `blueprint-test-lint/fresh-template-component-no-dangling-dep`.

- **`blueprint-rename-component` corrompeva dipendenze con trattino**: la
  sostituzione in `#+BLUEPRINT_DEPENDS:` usava `\\b%s\\b`, e `\\b` considera
  `-` un confine di parola: rinominare `auth` in `identity` trasformava
  `auth-db` in `identity-db` (componente inesistente); riscriveva anche le
  righe d'esempio nei blocchi src. **Fix**: `blueprint--rename-dependency`
  confronta token interi separati da spazi, su keyword trovate via
  `org-element`. Test: `blueprint-test-rename-component/hyphenated-dep-untouched`,
  `.../src-block-example-untouched`.

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

- **`blueprint-export.el` — didascalie dei diagrammi perse nell'export**:
  Babel sostituisce un blocco `:exports results` (default di
  ob-plantuml) con il suo `#+RESULTS:` e cancella le keyword affiliate
  del blocco, `#+CAPTION:` compreso. Nessun hook di export cade fra
  l'espansione degli `#+INCLUDE:` e Babel. **Fix**:
  `blueprint--move-result-captions`, advice `:around` su
  `org-babel-exp-process-buffer`: prima di Babel una riga-sentinella dopo
  i risultati (o dopo il blocco, se non ne ha), dopo Babel
  `#+CAPTION:`/`#+NAME:`/`#+ATTR_*:` sul paragrafo `#+RESULTS:` che
  precede la sentinella. Copre anche i blocchi valutati per la prima volta
  durante l'export. Test: `blueprint-test-export/caption-*`,
  `.../odt-caption-reaches-content-xml`.

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

- **`blueprint-health.el` — gauge SVG mai visibile in Emacs**:
  `blueprint-health-svg` apriva `health.svg` con `find-file`, cioè in
  `image-mode`. Con Emacs compilato con ImageMagick,
  `image--imagemagick-wanted-p` passa ogni file a ImageMagick (salvo le
  estensioni in `imagemagick-types-inhibit`), e la security policy di
  ImageMagick di molte distribuzioni vieta SVG: restava un riquadro vuoto.
  Il file inoltre non dichiarava `xmlns` (browser e LibreOffice non lo
  riconoscono come SVG) e aveva sfondo trasparente con tratti neri
  (invisibili con un tema scuro). **Fix**: il file si scrive ancora, ma si
  mostra nel buffer `*Blueprint Health*` con `create-image` di tipo `svg`
  (librsvg nativo); `blueprint--health-svg-string` produce un documento con
  namespace e sfondo bianco. Verificato con screenshot sotto Xvfb (per una
  build PGTK serve `env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:N`,
  altrimenti la finestra si apre sulla sessione Wayland). Test:
  `blueprint-test-health-svg/*`.

- **Copie in sola lettura da un'installazione read-only (CI rossa da
  settembre)**: `copy-file` conserva i permessi della sorgente. Con Org o
  Blueprint installati in uno store in sola lettura (in CI
  `purcell/setup-emacs` usa Nix, file 0444) le copie restavano 0444:
  `blueprint-test--odt-styles-copy` apriva `styles.xml` in un buffer
  read-only e il test `odt-styles-check-detects-missing-style` falliva su
  tutte le versioni (in locale passava, file 0644). Lo stesso colpiva il
  pacchetto: `blueprint--provision-user-templates` e
  `blueprint-template-migrate` producevano template "modificabili" non
  scrivibili. **Fix**: `blueprint--copy-file-writable` (`blueprint-core.el`)
  aggiunge il bit di scrittura del proprietario dopo la copia; il fixture
  di test scrive il file da un buffer. La matrice CI ora ha
  `fail-fast: false`, perché un fallimento su una versione cancellava le
  altre. Per provare in locale Emacs 29:
  `docker run --rm -v "$PWD":/src:ro silex/emacs:29.1 ...`. Test:
  `blueprint-test-migrate/copies-are-writable-from-read-only-source`,
  `.../provisioned-user-templates-writable`.

- **Template di componente senza scheletro**: `component.org`,
  `functional.org` e `infrastructure.org` avevano, fuori dalla guida, prosa
  segnaposto, tabelle vuote, diagrammi PlantUML d'esempio e un
  `[DA VALIDARE]` per sezione: tutto testo esportato, per cui il lint non
  segnalava mai un componente mai compilato. Ora il corpo contiene solo
  heading e ancore `<<{{ID}}-...>>`; descrizioni delle sezioni e modelli
  (tabelle, diagrammi) stanno nella guida `:noexport:`. I blocchi PlantUML
  della guida hanno `:eval never`: Babel valuta anche i blocchi dei
  sottoalberi `:noexport:` (verificato: senza, ogni export genera gli svg).
  Il lint non conta come contenuto le righe con sola ancora. Non toccati:
  gli altri template (master, enterprise, nfr, glossary, references, adr) e
  lo scheletro che i comandi `blueprint-functional-add-*` /
  `blueprint-runtime-add-*` inseriscono per le sezioni che creano.

## Health scoring

Score starts at 100, deducting per unresolved marker across all component files:

- **Technical markers**: `QUESTION` = −3, `TBD` = −2, `FIXME` = −4
- **Methodology markers**: `[DA VALIDARE]` = −1, `[FINDING]` = −2,
  `[DA REVISIONARE]` = −1

Only markers in exported text count: `blueprint--uncounted-regions`
(`blueprint-core.el`) excludes export-excluded subtrees (`:noexport:`,
`#+EXCLUDE_TAGS:`), COMMENT subtrees, src/example/export/comment blocks,
comments and verbatim/code objects; matching is case-sensitive. Use
`blueprint--count-file-markers` / `blueprint--marker-positions` for any new
marker scan instead of `count-matches` on raw text. Keywords
(`#+STATUS: [DA VALIDARE]`) still count. The lint "no content" check
ignores lines in non-exported subtrees (`blueprint--non-exported-subtrees`)
but, unlike marker counting, still treats src blocks and verbatim as
content.

Clamped to 0 minimum. Technical marker results cached by MD5 via
`blueprint--cached-metrics`. Methodology markers counted separately via
`blueprint--methodology-metrics` (not cached — avoids cache key collision with
the existing cache keyed by file path).

`blueprint-list-findings` and `blueprint-list-unvalidated` scan all `.org` files
in the project and display results in a read-only buffer.
`blueprint--display-marker-list` captures `(blueprint--root)` **before**
`(with-current-buffer ...)` to avoid stale `default-directory` from pre-existing
result buffers (isolation-critical for tests).
