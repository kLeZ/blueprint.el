# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Blueprint.el is an Emacs Lisp package for text-first architectural assessment using Org-mode and Arc42 methodology. It generates C4 diagrams (PlantUML) and dependency graphs (Graphviz), managed through a Transient menu at `C-c b`.

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
  -l test/blueprint-test-helpers.el \
  -l test/blueprint-test-core.el -l test/blueprint-test-health.el \
  -l test/blueprint-test-lint.el -l test/blueprint-test-c4.el \
  -l test/blueprint-test-adr.el -l test/blueprint-test-sync.el \
  -l test/blueprint-test-content.el -l test/blueprint-test-risks.el \
  -l test/blueprint-test-ai.el -l test/blueprint-test-e2e.el \
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

Bump `;;  Version: X.Y.Z` in `blueprint.el` header and push to `main` — the release workflow creates the git tag and GitHub release automatically.

## Architecture

All modules depend on `blueprint-core.el`, which provides:
- `blueprint--root` — locates `.blueprint/` directory by walking up the tree
- `blueprint--components` — returns a hash table `{name → dir}` of all components
- `blueprint--cached-metrics` / `blueprint--invalidate-cache` — MD5-based cache for component metrics
- `blueprint--resolve-template` — three-tier template lookup (project → user → system)

The entry point `blueprint.el` only wires the Transient menu and `require`s all modules; no logic lives there.

`blueprint-roam.el` is a soft dependency loaded with `(require 'blueprint-roam nil t)` in `blueprint.el`.

### Data flow for a typical command

1. Command reads `blueprint--root` to find `.blueprint/`
2. Calls `blueprint--components` to enumerate `arc42.org` files
3. Parses files via `org-element` (never regex on Org content)
4. Uses `blueprint--cached-metrics` to avoid re-reading unchanged files
5. Writes output (`.puml`, `.svg`, buffer) to project root

### Template system (three-tier resolution)

| Priority | Path | Purpose |
|----------|------|---------|
| 1 | `.blueprint/templates/` | Project-local overrides |
| 2 | `~/.config/blueprint/templates/` | User defaults |
| 3 | `templates/` in package dir | System fallback |

Template files: `component.org`, `adr.org`, `master.org`, `functional.org`,
`infrastructure.org`, `glossary.org`, `references.org`, `enterprise-context.org`,
`enterprise-dependencies.org`, `nfr-quality.org`, `nfr-constraints.org`, `nfr-risks.org`.

Placeholders: `{{NAME}}` (component name), `{{ID}}` (slugified, for directory names and
PlantUML IDs), `{{PROJECT}}`, `{{AUTHOR}}`, `{{DATE}}`.

**Template provisioning**: When `blueprint-init` is called interactively, it checks
`~/.config/blueprint/templates/`. If any template is missing, it copies the system
templates there and shows a prominent message listing every file written to the user's
home. This ONLY happens interactively (not in batch/tests — uses
`(called-interactively-p 'interactive)`).

### Key Org keyword

`#+BLUEPRINT_DEPENDS: comp1 comp2` in a component's `arc42.org` is the sole mechanism for declaring inter-component dependencies. C4 diagram generation and the dependency graph both parse this keyword.

## Code conventions

- All files: `;;; -*- lexical-binding: t; -*-`
- Public symbols: `blueprint-` prefix; private: `blueprint--` (double dash)
- `;;;###autoload` on all interactive public commands
- `defcustom` for all user-facing settings, group `blueprint`
- Parse Org files with `org-element`, never with regex
- Optional integrations: `(require 'feature nil t)`

## Test structure

Tests in `test/` usano ERT. Il macro `blueprint-test--with-project` crea una
directory temporanea con struttura `.blueprint/` e la pulisce dopo ogni test.

| File | Scope |
|------|-------|
| `blueprint-test-helpers.el` | Macro e utility condivise |
| `blueprint-test-core.el` | Root, cache, CRUD |
| `blueprint-test-health.el` | Metriche e health score |
| `blueprint-test-lint.el` | Linter (incluso fix file mancante) |
| `blueprint-test-c4.el` | Keyword extraction, C4 gen |
| `blueprint-test-adr.el` | ADR numerazione e creazione |
| `blueprint-test-sync.el` | Master sync e marker |
| `blueprint-test-content.el` | Glossario, riferimenti, domande |
| `blueprint-test-risks.el` | Pattern matching e check strutturali |
| `blueprint-test-ai.el` | Sanitizzazione e clamping (no Ollama) |
| `blueprint-test-e2e.el` | Lifecycle completo di un progetto |

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

`blueprint-sync` manages three independent `#+INCLUDE:` sections in `master.org`:

| Marker pair | File synced |
|-------------|-------------|
| `@@blueprint-sync-start@@` / `@@blueprint-sync-end@@` | `arc42.org` |
| `@@blueprint-sync-functional-start@@` / `-end@@` | `functional.org` |
| `@@blueprint-sync-infra-start@@` / `-end@@` | `infrastructure.org` |

Missing marker pairs are silently skipped (backward compatible).
`blueprint--generate-includes-for` only emits includes for components that
actually have the file (prevents spurious includes for partially migrated projects).

## Assessment methodology

Templates follow the methodology from `assessment-framework/methodology/METHOD.org`:

- **Information source hierarchy**: code > tests > logs > monitoring > interviews > docs
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
  quando `file` era nil o mancante (il `(list ...)` nella branch `then` dell'`if`
  veniva scartato; `(nreverse warnings)` era sempre l'ultima espressione).
  **Fix**: struttura `if` riscritta con l'intera logica nella branch `else`.

- **`BLUEPRINT_DEPENDS` regex**: `\\s-*` in Elisp include i newline (tramite la
  syntax class whitespace). In `"^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)"` il
  pattern poteva catturare testo dalla riga successiva (es. `"* Introduction"`),
  causando falsi positivi nel controllo dipendenze isolate.
  **Fix**: sostituito con `[[:blank:]]*` (solo spazi/tab orizzontali) in
  `blueprint-risks.el`, `blueprint-dashboard.el`, `blueprint-ci.el`,
  `blueprint-lint.el`.

- **`test/blueprint-test-e2e.el`**: parentesi sbilanciata nell'`ert-deftest`
  `multi-component-c4` — mancava un `)` finale.
  **Fix**: aggiunto `)` alla fine della riga 143.

## Health scoring

Score starts at 100, deducting per unresolved marker across all component files:
`QUESTION` = −3, `TBD` = −2, `FIXME` = −4. Clamped to 0 minimum. Results cached by MD5.
