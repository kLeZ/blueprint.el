# Blueprint Ultra

Text-first architectural assessment toolkit for Emacs.

Blueprint Ultra helps software architects and technical leads document,
visualize, and assess software architecture directly from Emacs using
plain-text Org-mode files. It follows a component-based approach inspired
by the [Arc42](https://arc42.org/) documentation methodology.

## Features

- **C4 diagram generation** — produces PlantUML C4 container diagrams by
  parsing `#+BLUEPRINT_DEPENDS:` keywords from component files
- **Health score gauge** — calculates a quality score based on open
  questions, TBDs, and FIXMEs, and renders it as an SVG semicircular gauge
- **Template system** — three-tier template hierarchy (project, user,
  system) with diff and non-destructive migration tools
- **Transient menu** — all commands accessible through a single `C-c b`
  keybinding via the Transient menu system

## Requirements

| Dependency       | Required | Purpose                          |
|------------------|----------|----------------------------------|
| Emacs 29+        | yes      | Core platform                    |
| transient        | yes      | Menu system (bundled with Emacs) |
| PlantUML         | optional | Render C4 diagrams               |
| Graphviz (dot)   | optional | Alternative diagram rendering    |

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
5. Generate a C4 diagram with `C-c b C` or a health SVG with `C-c b H`.

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

The `arc42.org` template contains sections for **Responsibility**, **Risks**,
and **Questions**, plus a `#+BLUEPRINT_DEPENDS:` keyword for declaring
dependencies.

### Declaring dependencies

In any component's `arc42.org` file, list space-separated dependency names:

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

Render the diagram with PlantUML or a compatible tool.

### Health scoring

`blueprint-health-score` computes a quality score starting at 100 and
deducting points for markers found across all component files:

| Marker     | Penalty |
|------------|---------|
| `QUESTION` | -3      |
| `TBD`      | -2      |
| `FIXME`    | -4      |

The score is clamped to a minimum of 0.

`blueprint-health-svg` generates a semicircular gauge visualization as
an SVG file (`health.svg`) in the project root and opens it in Emacs.

### Template management

Blueprint uses a three-tier template resolution order:

1. **Project templates** — `.blueprint/templates/` in the project root
2. **User templates** — `~/.config/blueprint/templates/`
3. **System templates** — `templates/` in the Blueprint package directory

When resolving a template, the first match wins. This allows projects
and users to override system defaults.

- `blueprint-template-diff` — shows a unified diff between system and
  project templates (non-destructive, read-only)
- `blueprint-template-migrate` — copies missing template files from
  system defaults into the project (never overwrites existing files)

## Customization

All customization options are in the `blueprint` customize group
(`M-x customize-group RET blueprint`):

| Variable                       | Default                              | Description                        |
|--------------------------------|--------------------------------------|------------------------------------|
| `blueprint-template-dir`       | `templates/` in package directory    | System-level templates directory   |
| `blueprint-user-template-dir`  | `~/.config/blueprint/templates`      | User-level templates directory     |

## Project structure

```
blueprint.el/
├── blueprint.el           # Main entry point, transient menu, keybinding
├── blueprint-core.el      # Project detection, component management, templates
├── blueprint-c4.el        # C4 PlantUML diagram generation
├── blueprint-health.el    # Health scoring and SVG gauge
├── blueprint-migrate.el   # Template diff and migration
├── templates/
│   └── component.org      # Default component template
└── README.md
```

## License

See the repository for license information.
