# Blueprint

Text-first architectural assessment toolkit for GNU Emacs.

Blueprint helps software architects and technical leads document,
visualize, and assess software architecture directly from Emacs using
plain-text Org-mode files. It follows a component-based approach inspired
by the [Arc42](https://arc42.org/) documentation methodology and produces
[C4 model](https://c4model.com/) diagrams via PlantUML.

## Background and rationale

Blueprint started life as a Python CLI tool (`scaffold.py`) for
generating and managing Arc42-based assessment documents. The Python
version handled project initialization, component CRUD, glossary
management, status reporting (tag scanning), master-file synchronization,
and export via Pandoc.

The rewrite in Emacs Lisp was motivated by a single observation: the
entire workflow already lived inside Emacs and Org mode. Shelling out to
Python for file manipulation that Org can do natively was unnecessary
friction. The goals for the Emacs port were:

1. **Full feature parity** with the Python original — no "MVP, we'll see
   later" compromises.
2. **Idiomatic Emacs Lisp** — leverage `org-element` AST parsing instead
   of fragile regex hacks, use the native Org exporter instead of Pandoc,
   and integrate with Transient for a discoverable UI.
3. **Zero mandatory external dependencies** — only Emacs 29+ and the
   bundled Transient library are required. PlantUML and Graphviz are
   optional for rendering.
4. **Offline-first, text-first, versionable** — every artifact is plain
   text. No databases, no cloud services, no lock-in.

The name changed from "scaffold" (too generic, evokes CRUD generators) to
**blueprint** — cleaner, more architectural, and appropriate for a tool
that helps you reason about software structure.

## Design decisions

### Why Transient instead of plain keybindings

Raw keybindings (`C-c s a`, `C-c s r`, `C-c s q`, …) are invisible, not
discoverable, and hard to remember after two weeks away from the project.
[Transient](https://magit.vc/manual/transient/) — the same framework
behind Magit — provides a self-documenting popup menu with logical groups.
One keybinding (`C-c b`) opens the entire command surface.

This is the same UX pattern that makes Magit feel like a "real tool"
rather than a collection of scattered commands.

### Three-tier template system

Templates **cannot** be hardcoded in the package. During a typical 12-day
co-design engagement with a client, the skeleton documents evolve
continuously. Blueprint solves this with a three-tier resolution order:

| Priority | Location                         | Purpose                        |
|----------|----------------------------------|--------------------------------|
| 1        | `.blueprint/templates/`          | Project-local overrides        |
| 2        | `~/.config/blueprint/templates/` | Personal defaults across projects |
| 3        | `templates/` in package dir      | System fallback (read-only)    |

The first match wins. You can clone system defaults into a project
(`blueprint-template-migrate`), customize them for the engagement, and
version them alongside the assessment. The system defaults remain
untouched as a fallback.

### Component-based structure

Each component gets its own directory under `.blueprint/components/` with
an `arc42.org` file. This keeps concerns separated and allows the master
document to assemble components via `#+INCLUDE:` directives. Dependencies
between components are declared with a simple Org keyword:

```org
#+BLUEPRINT_DEPENDS: auth database cache
```

These declarations are parsed to generate C4 container diagrams — no
manual diagramming required.

### Health scoring as motivation

The health score (0–100) penalizes markers like `QUESTION`, `TBD`, and
`FIXME` left in component files. It is intentionally simple — a gamified
nudge to clean up open items rather than a rigorous metric. The SVG gauge
makes it visual enough to show a client during a review session.

## Features

- **Project initialization** — creates `.blueprint/` directory structure
  with `components/` and `adr/` subdirectories
- **Component management** — full CRUD: add, list, rename, and delete
  components, each with its own `arc42.org` documentation file
- **Component skeleton wizard** — interactive prompts for name,
  responsibility, owner, and tech stack that pre-fill the template
- **Wizard onboarding** — guided step-by-step project setup
- **C4 diagram generation** — produces PlantUML C4 container diagrams by
  parsing `#+BLUEPRINT_DEPENDS:` keywords from component files
- **Dependency graph** — PlantUML/Graphviz visualization of component
  dependencies with health-based coloring
- **Health score gauge** — calculates a quality score and renders it as an
  SVG semicircular gauge with metrics caching
- **Dashboard buffer** — Magit-style status buffer showing all components
  with metrics (questions, TBDs, FIXMEs, lines, status indicators),
  navigable with `RET` to open component files
- **Focus mode** — filtered dashboard showing only components that need
  attention
- **SVG dashboard** — Graphviz-based visual overview with risk-based
  coloring
- **Glossary management** — structured glossary with terms, definitions,
  and source attribution
- **Reference tracking** — document, interview, and system references
- **Open questions** — AST-based insertion into component `arc42.org`
  files using `org-element` (no regex)
- **Master file sync** — automatic synchronization of `#+INCLUDE:`
  directives in the master document
- **Linter** — validation rules (missing headings, excessive unresolved
  markers, dangling dependencies, empty content) with headless/CI support
- **Org-native export** — PDF, HTML, and DOCX export using the Org
  exporter (DOCX requires `ox-pandoc`)
- **Async tangle/export** — background processing via Emacs 29+ threads
  to avoid blocking the UI
- **Auto-tangle on save** — minor mode for automatic `org-babel-tangle`
  when saving `.org` files in a Blueprint project
- **Watch mode** — `after-save-hook` minor mode for automatic cache
  invalidation, master sync, and C4 regeneration
- **Rule-based risk suggestions** — deterministic pattern matching against
  component text to suggest common architectural risks (single point of
  failure, unclear ownership, missing monitoring, etc.)
- **AI-assisted snippets (Ollama)** — optional local LLM integration for
  section expansion, risk suggestion, and boilerplate generation. Fully
  offline, no data leaves the machine. Falls back to rule-based
  suggestions when Ollama is not running
- **Prompt guardrails** — context clamping, character limits, and
  sanitization (emails, IPs, passwords) for LLM prompts
- **Architecture Decision Records (ADR)** — automatic ADR creation and
  management in `.blueprint/adr/` with numbered files and status tracking
- **Ripgrep search** — project-wide search with predefined queries for
  open questions, TBDs, and FIXMEs (falls back to grep)
- **Quick capture** — `org-capture`-style note taking for notes,
  questions, and glossary terms
- **Daily workflow command** — one-key triage sequence (dashboard → focus →
  select component → edit)
- **Org-roam integration** — components as navigable org-roam nodes with
  backlink support (requires `org-roam`)
- **CI/headless mode** — `emacs --batch` entry points for linting,
  validation, and export with appropriate exit codes
- **Metrics caching** — MD5-based hash-table cache invalidated on file
  change for instant dashboard rendering on large projects
- **Template system** — three-tier hierarchy with diff and non-destructive
  migration tools
- **Transient menu** — all commands accessible through `C-c b`

## Requirements

| Dependency   | Required | Purpose                                |
|--------------|----------|----------------------------------------|
| Emacs 29+    | yes      | Core platform (threads for async)      |
| transient    | yes      | Menu system (bundled with Emacs)       |
| PlantUML     | optional | Render C4 and dependency diagrams      |
| Graphviz     | optional | SVG dashboard and dependency graphs    |
| Ollama       | optional | Local LLM for AI-assisted snippets     |
| ox-pandoc    | optional | DOCX export                            |
| org-roam     | optional | Component backlink navigation          |

## Installation

### Manual

Clone the repository and add it to your load path:

```elisp
(add-to-list 'load-path "/path/to/blueprint.el")
(require 'blueprint)
(global-set-key (kbd "C-c b") #'blueprint-menu)
```

### use-package

```elisp
(use-package blueprint
  :load-path "/path/to/blueprint.el"
  :bind ("C-c b" . blueprint-menu))
```

### straight.el

```elisp
(straight-use-package
 '(blueprint :type git :host github :repo "kLeZ/blueprint.el"))
```

## Quick start

1. Open a directory in Emacs where you want to create an architecture
   project.
2. Run `M-x blueprint-wizard-init` (or `C-c b W`) for a guided setup,
   or `M-x blueprint-init` (or `C-c b I`) for manual initialization.
3. Add a component with `M-x blueprint-add-component` (or `C-c b A`)
   for a simple component, or `M-x blueprint-wizard-component`
   (`C-c b w`) for a pre-filled wizard.
4. Edit the `arc42.org` file to document the component's responsibility,
   risks, questions, and dependencies.
5. Declare dependencies with `#+BLUEPRINT_DEPENDS: other-component`.
6. Open the dashboard with `C-c b B` to see all components at a glance.
7. Generate a C4 diagram with `C-c b C`, a dependency graph with
   `C-c b G`, or a health SVG with `C-c b H`.
8. Run `C-c b L` to lint the project, `C-c b s` for risk suggestions.

## Usage

Press `C-c b` to open the Blueprint transient menu. The menu is organized
into logical groups:

| Group        | Key | Command                |
|--------------|-----|------------------------|
| **Project**  | `I` | init                   |
|              | `W` | wizard init            |
|              | `A` | add component          |
|              | `w` | wizard component       |
|              | `R` | rename component       |
|              | `X` | delete component       |
|              | `l` | list components        |
| **Architecture** | `C` | generate C4        |
|              | `G` | dependency graph       |
|              | `S` | sync master            |
| **Quality**  | `H` | health SVG             |
|              | `L` | lint                   |
|              | `s` | suggest risks          |
| **Dashboard**| `B` | dashboard              |
|              | `F` | focus mode             |
|              | `.` | daily workflow         |
| **Content**  | `Q` | add question           |
|              | `q` | list questions         |
|              | `Y` | glossary               |
|              | `y` | add glossary term      |
|              | `Z` | references             |
|              | `z` | add reference          |
| **Templates**| `D` | diff                   |
|              | `M` | migrate                |
| **Export**   | `E` | export (default)       |
|              | `P` | export PDF             |
|              | `T` | async tangle           |
| **Search & ADR** | `/` | search             |
|              | `N` | new ADR                |
|              | `n` | list ADRs              |
|              | `K` | capture                |

### Initializing a project

`blueprint-init` creates the following structure in the current directory:

```
.blueprint/
├── components/   # One subdirectory per component
└── adr/          # Architecture Decision Records
```

### Adding components

`blueprint-add-component` prompts for a component name and creates:

```
.blueprint/components/<name>/
└── arc42.org     # Component documentation (from template)
```

The `arc42.org` template contains full Arc42 sections (Introduction,
Context and Scope, Constraints, Solution Strategy, Building Blocks,
Runtime Behavior, Deployment, Responsibility, Risks, Open Questions,
Diagrams), plus a `#+BLUEPRINT_DEPENDS:` keyword for declaring
dependencies.

### Declaring dependencies

In any component's `arc42.org` file, list space-separated dependency
names:

```org
#+BLUEPRINT_DEPENDS: auth database
```

These are parsed by the C4 generator to produce relationship arrows.

### Generating C4 diagrams

`blueprint-generate-c4` reads all components and their
`#+BLUEPRINT_DEPENDS:` keywords, then writes a `c4.puml` file to the
project root. The output uses PlantUML's C4 Container syntax:

```plantuml
@startuml
!include C4_Container.puml
Container(api, "api", "component")
Container(auth, "auth", "component")
Rel(api, auth, "uses")
@enduml
```

Render with PlantUML or a compatible tool.

### Health scoring

`blueprint-health-score` computes a quality score starting at 100 and
deducting points for markers found across all component files:

| Marker     | Penalty |
|------------|---------|
| `QUESTION` | -3      |
| `TBD`      | -2      |
| `FIXME`    | -4      |

The score is clamped to a minimum of 0. Results are cached using MD5
hashes and automatically invalidated when files change.

`blueprint-health-svg` generates a semicircular gauge as an SVG file
(`health.svg`) in the project root and opens it in Emacs.

### Dashboard

`blueprint-dashboard` opens a `tabulated-list-mode` buffer showing all
components with columns for Questions, TBDs, FIXMEs, Lines, and Status.
Navigation: `RET` opens a component, `g` refreshes, `F` toggles focus
mode, `q` closes.

### Template management

Blueprint uses a three-tier template resolution order:

1. **Project templates** — `.blueprint/templates/` in the project root
2. **User templates** — `~/.config/blueprint/templates/`
3. **System templates** — `templates/` in the Blueprint package directory

When resolving a template, the first match wins. This allows projects and
users to override system defaults without modifying the package.

- `blueprint-template-diff` — shows a unified diff between system and
  project templates (read-only)
- `blueprint-template-migrate` — copies missing template files from system
  defaults into the project (never overwrites existing files)

### CI / headless usage

Blueprint provides dedicated batch-mode entry points with exit codes:

```sh
# Lint all components (exit 0=pass, 1=warnings)
emacs -Q --batch -l blueprint.el -f blueprint-ci-lint

# Full validation: lint + health + dependency check (0=pass, 1=warn, 2=error)
emacs -Q --batch -l blueprint.el -f blueprint-ci-validate

# Export (exit 0=pass, 2=error)
emacs -Q --batch -l blueprint.el -f blueprint-ci-export
```

### AI-assisted snippets

When Ollama is running locally, Blueprint can use it for:

- `blueprint-ai-expand` — expand the current section with AI-generated
  content
- `blueprint-ai-suggest-risks` — suggest architectural risks (falls back
  to rule-based suggestions when Ollama is unavailable)
- `blueprint-ai-boilerplate` — generate professional boilerplate for
  empty sections

All prompts include guardrails: context clamping to
`blueprint-ai-max-context` characters, and sanitization of emails, IP
addresses, and password-like patterns.

## Customization

All customization options are in the `blueprint` customize group
(`M-x customize-group RET blueprint`):

| Variable                        | Default                           | Description                        |
|---------------------------------|-----------------------------------|------------------------------------|
| `blueprint-template-dir`        | `templates/` in package directory | System-level templates directory   |
| `blueprint-user-template-dir`   | `~/.config/blueprint/templates`   | User-level templates directory     |
| `blueprint-lint-marker-threshold` | `5`                             | Marker count before lint warns     |
| `blueprint-export-backend`      | `pdf`                             | Default export format              |
| `blueprint-graph-backend`       | `plantuml`                        | Dependency graph renderer          |
| `blueprint-watch-auto-sync`     | `nil`                             | Auto-sync master on save           |
| `blueprint-watch-auto-c4`       | `nil`                             | Auto-regenerate C4 on save         |
| `blueprint-ai-model`            | `llama3`                          | Ollama model name                  |
| `blueprint-ai-endpoint`         | `http://localhost:11434`          | Ollama API URL                     |
| `blueprint-ai-max-context`      | `4000`                            | Max chars sent to LLM              |

## Architecture

Blueprint is organized as a set of focused modules, each handling one
concern:

```
blueprint.el/
├── blueprint.el             # Entry point, transient menu, requires all modules
├── blueprint-core.el        # Root detection, components, templates, cache, CRUD
├── blueprint-c4.el          # C4 PlantUML generation
├── blueprint-health.el      # Health scoring and SVG gauge
├── blueprint-migrate.el     # Template diff and migration
├── blueprint-adr.el         # ADR creation and listing
├── blueprint-lint.el        # Linter with CI support
├── blueprint-dashboard.el   # Dashboard buffer, focus mode, SVG dashboard
├── blueprint-questions.el   # Open questions (AST-based)
├── blueprint-glossary.el    # Glossary management
├── blueprint-references.el  # Reference tracking
├── blueprint-sync.el        # Master file synchronization
├── blueprint-search.el      # Ripgrep/grep project search
├── blueprint-export.el      # Org-native export (PDF, HTML, DOCX)
├── blueprint-async.el       # Background threads for export/tangle
├── blueprint-watch.el       # Auto-tangle and watch minor modes
├── blueprint-graph.el       # Dependency graph (PlantUML/Graphviz)
├── blueprint-wizard.el      # Component and project wizards
├── blueprint-capture.el     # org-capture integration
├── blueprint-daily.el       # Daily workflow command
├── blueprint-risks.el       # Rule-based risk suggestions
├── blueprint-ai.el          # Ollama AI integration + guardrails
├── blueprint-roam.el        # org-roam integration (optional)
├── blueprint-ci.el          # CI/headless batch commands
├── templates/
│   ├── component.org        # Default Arc42 component template
│   ├── adr.org              # ADR template
│   └── master.org           # Master document template
└── README.md
```

All modules depend on `blueprint-core` for project root detection,
component enumeration, template resolution, and metrics caching. The
entry point (`blueprint.el`) wires everything together and exposes the
transient menu.

## Contributing

Contributions are welcome. The guiding principles for this project:

- **Keep it simple** — each module should be understandable in minutes.
- **No external runtime dependencies** — PlantUML, Graphviz, Ollama, and
  org-roam are optional backends, not requirements.
- **Text-first** — every artifact must be plain text and version-control
  friendly.
- **Emacs-idiomatic** — use `org-element` over regex when parsing Org
  files, use Transient for UI, use `defcustom` for configuration.

## License

See the repository for license information.
