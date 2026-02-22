# Blueprint Ultra

Text-first architectural assessment toolkit for GNU Emacs.

Blueprint Ultra helps software architects and technical leads document,
visualize, and assess software architecture directly from Emacs using
plain-text Org-mode files. It follows a component-based approach inspired
by the [Arc42](https://arc42.org/) documentation methodology and produces
[C4 model](https://c4model.com/) diagrams via PlantUML.

## Background and rationale

Blueprint Ultra started life as a Python CLI tool (`scaffold.py`) for
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
One keybinding (`C-c b`) opens the entire command surface:

```
Architecture   Quality    Templates  Project
C generate C4  H health   D diff     I init
                          M migrate  A add
```

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

### Implemented

- **Project initialization** — creates `.blueprint/` directory structure
  with `components/` and `adr/` subdirectories
- **Component management** — add components from templates, each with its
  own `arc42.org` documentation file
- **C4 diagram generation** — produces PlantUML C4 container diagrams by
  parsing `#+BLUEPRINT_DEPENDS:` keywords from component files
- **Health score gauge** — calculates a quality score and renders it as an
  SVG semicircular gauge
- **Template system** — three-tier hierarchy with diff and non-destructive
  migration tools
- **Transient menu** — all commands accessible through `C-c b`

### Roadmap

The following features were designed during the original architecture
sessions and are planned for future implementation:

- **Dashboard buffer** — Magit-style status buffer showing all components
  with metrics (questions, findings, review items, lines, status
  indicators), navigable with `RET` to open component files
- **Glossary management** — structured glossary with terms, definitions,
  and source attribution
- **Reference tracking** — document, interview, and system references
- **Open questions** — AST-based insertion into component `arc42.org`
  files (no regex)
- **Master file sync** — automatic synchronization of `#+INCLUDE:`
  directives in the master document
- **Org-native export** — PDF and DOCX export using the Org exporter
  (Pandoc available as optional alternative for corporate formats)
- **Async tangle/export** — background processing via threads to avoid
  blocking Emacs
- **Auto-tangle on save** — automatic `org-babel-tangle` when saving
  `.org` files in a Blueprint project
- **Watch mode** — `after-save-hook` integration for automatic master sync
- **Dependency graph** — PlantUML/Graphviz visualization of component
  dependencies with `#+BLUEPRINT_DEPENDS:` parsing
- **SVG dashboard** — Graphviz-based visual overview with risk-based
  coloring
- **Linter** — validation rules (missing headings, excessive unvalidated
  tags) with headless/CI support
- **Focus mode** — filtered dashboard showing only components that need
  attention
- **Quick capture** — `org-capture`-style note taking into project notes
- **Wizard onboarding** — guided step-by-step project setup
- **Daily workflow command** — one-key triage sequence (dashboard → focus →
  edit → sync → export)
- **Rule-based risk suggestions** — deterministic pattern matching against
  component text to suggest common architectural risks (single point of
  failure, unclear ownership, missing monitoring, etc.)
- **AI-assisted snippets (Ollama)** — optional local LLM integration for
  section expansion, risk suggestion, and boilerplate generation. Fully
  offline, no data leaves the machine. Falls back to rule-based
  suggestions when Ollama is not running
- **Prompt guardrails** — context clamping and character limits for LLM
  prompts
- **Architecture Decision Records (ADR)** — automatic ADR creation and
  management in `.blueprint/adr/`
- **Ripgrep search** — project-wide search with predefined queries for
  open questions, TBDs, and validation tags
- **Org-roam integration** — components as navigable nodes with backlink
  support
- **CI/headless mode** — `emacs --batch` invocation for linting, tangling,
  and validation in CI pipelines
- **Metrics caching** — hash-table cache invalidated on save for instant
  dashboard rendering on large projects
- **Component skeleton wizard** — interactive prompts for name,
  responsibility, owner, and tech stack that pre-fill the template

## Requirements

| Dependency   | Required | Purpose                          |
|--------------|----------|----------------------------------|
| Emacs 29+    | yes      | Core platform                    |
| transient    | yes      | Menu system (bundled with Emacs) |
| PlantUML     | optional | Render C4 diagrams               |
| Graphviz     | optional | Alternative diagram rendering    |
| Ollama       | optional | Local LLM for AI-assisted snippets (planned) |

## Installation

### Manual

Clone the repository and add it to your load path:

```elisp
(add-to-list 'load-path "/path/to/blueprint.el")
(require 'blueprint)
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
2. Run `M-x blueprint-init` (or `C-c b I`) to initialize the project.
   This creates a `.blueprint/` directory with `components/` and `adr/`
   subdirectories.
3. Add a component with `M-x blueprint-add-component` (or `C-c b A`).
   Enter a name when prompted — a directory with an `arc42.org` template
   file is created under `.blueprint/components/<name>/`.
4. Edit the `arc42.org` file to document the component's responsibility,
   risks, questions, and dependencies.
5. Declare dependencies with `#+BLUEPRINT_DEPENDS: other-component`.
6. Generate a C4 diagram with `C-c b C` or a health SVG with `C-c b H`.

## Usage

Press `C-c b` to open the Blueprint transient menu:

```
┌─────────────────────────────────────────────┐
│ Architecture   Quality    Templates  Project│
│ C generate C4  H health   D diff     I init │
│                           M migrate  A add  │
└─────────────────────────────────────────────┘
```

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

The `arc42.org` template contains sections for **Responsibility**,
**Risks**, and **Questions**, plus a `#+BLUEPRINT_DEPENDS:` keyword for
declaring dependencies.

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

The score is clamped to a minimum of 0.

`blueprint-health-svg` generates a semicircular gauge as an SVG file
(`health.svg`) in the project root and opens it in Emacs.

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

Blueprint commands can be run non-interactively for CI pipelines:

```sh
emacs -Q --batch -l blueprint.el --eval "(blueprint-init)"
```

## Customization

All customization options are in the `blueprint` customize group
(`M-x customize-group RET blueprint`):

| Variable                      | Default                           | Description                      |
|-------------------------------|-----------------------------------|----------------------------------|
| `blueprint-template-dir`      | `templates/` in package directory | System-level templates directory |
| `blueprint-user-template-dir` | `~/.config/blueprint/templates`   | User-level templates directory   |

## Architecture

Blueprint is organized as a set of focused modules, each handling one
concern:

```
blueprint.el/
├── blueprint.el           # Entry point: requires all modules, defines
│                          # the transient menu, binds C-c b
├── blueprint-core.el      # Project root detection, component management,
│                          # template resolution (3-tier), init
├── blueprint-c4.el        # C4 PlantUML generation from BLUEPRINT_DEPENDS
├── blueprint-health.el    # Health scoring algorithm and SVG gauge
├── blueprint-migrate.el   # Template diff (via diff-mode) and
│                          # non-destructive migration
├── templates/
│   └── component.org      # Default Arc42 component template
└── README.md
```

This modular split keeps each file small and readable. You can open any
`.el` file and understand it in a couple of minutes — a deliberate choice
for a tool that is meant to be personally hackable.

### How the pieces connect

```
                    ┌──────────────┐
                    │ blueprint.el │  entry point + transient menu
                    └──────┬───────┘
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
 ┌────────────────┐ ┌───────────┐ ┌──────────────────┐
 │ blueprint-core │ │blueprint- │ │  blueprint-       │
 │    .el         │ │  c4.el    │ │  health.el        │
 │                │ │           │ │                    │
 │ root detection │ │ C4 puml   │ │ scoring + SVG     │
 │ components     │ │ generation│ │ gauge              │
 │ templates      │ │           │ │                    │
 │ init           │ └───────────┘ └──────────────────┘
 └────────────────┘
          ▲
          │
 ┌────────────────┐
 │ blueprint-     │
 │ migrate.el     │
 │                │
 │ template diff  │
 │ + migration    │
 └────────────────┘
```

All modules depend on `blueprint-core` for project root detection,
component enumeration, and template resolution. The entry point
(`blueprint.el`) simply wires everything together and exposes the
transient menu.

## Contributing

Contributions are welcome. The guiding principles for this project:

- **Keep it simple** — each module should be understandable in minutes.
- **No external runtime dependencies** — PlantUML, Graphviz, and Ollama
  are optional rendering/AI backends, not requirements.
- **Text-first** — every artifact must be plain text and version-control
  friendly.
- **Emacs-idiomatic** — use `org-element` over regex when parsing Org
  files, use Transient for UI, use `defcustom` for configuration.

## License

See the repository for license information.
