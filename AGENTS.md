# AGENTS.md

This file provides guidance to coding agents (Claude Code, opencode and other AGENTS.md-aware tools) when working with code in this repository. `CLAUDE.md` only imports this file (`@AGENTS.md`): edit this one.

## What this project is

Blueprint.el is an Emacs Lisp package for text-first architectural assessment using Org-mode and Arc42 methodology. It generates C4 diagrams (PlantUML) and dependency graphs (Graphviz), managed through a Transient menu at `C-c b`.

## No data from real engagements

The package is piloted on real client work, but nothing from that work belongs in this repository.

- Never write client, project, product, system, repository or people names from a real engagement anywhere in the repository: code, docstrings, tests, examples, templates, images, `PLAN.org`, `CHANGELOG.org`, `CONTEXT.org`, ADRs, commit messages, tags and release notes.
- Log defects and requests that come from real use as found on the "progetto pilota" (English: "pilot project"), with the date if useful, and without identifying details (names, internal paths, commit hashes, document titles).
- Test fixtures and examples use invented names (`acme--portale`, `GestioneMagazzino`), never values copied from a real project.

## Commands

### Tests and lint

The `Makefile` runs every check the CI runs, each in a clean `emacs -Q --batch`:

```sh
make test                  # whole ERT suite (loads every test/blueprint-test-*.el)
make test SELECTOR=health  # only the tests whose name matches the regexp
make compile               # byte-compile, warnings are errors (.elc removed after)
make checkdoc              # checkdoc on every module
make package-lint          # package-lint on blueprint.el (package-lint must be installed)
make lint                  # compile + checkdoc
```

A new test file needs no registration anywhere: `make test` picks it up.

### Before every commit

Run `scripts/fmt-docs.sh` before every commit (user rule, 2026-11-16): it formats every Org file (tables, src block indentation, `,#+` escapes) and the Markdown files, so a commit never carries the reformatting of files it did not touch. It also rewrites the templates: when it changes a file under `templates/`, run `scripts/gen-template-history.sh` afterwards, then `make test`.

### CI headless commands (from `blueprint-ci.el`)

```sh
emacs -Q --batch -l blueprint.el -f blueprint-ci-lint      # exit 0=ok, 1=warning
emacs -Q --batch -l blueprint.el -f blueprint-ci-validate  # exit 0=ok, 1=warn, 2=error
emacs -Q --batch -l blueprint.el -f blueprint-ci-export    # exit 0=ok, 2=error
```

### Releasing

Bump `;;  Version: X.Y.Z` in `blueprint.el` header and push to `main` — the release workflow creates the git tag and GitHub release automatically. Before the bump, run `scripts/gen-template-history.sh` and commit `blueprint-template-history.el` (MD5 of every version of every system template; `blueprint-test-upgrade/current-templates-are-in-history` fails when a template changed and the table was not regenerated).

Never push the `vX.Y.Z` tag together with `main`: the workflow skips the release when the tag already exists. The release asset is an uncompressed `.tar` with a `blueprint-pkg.el` generated from the header of `blueprint.el`, because `package-install-file` accepts neither a `.tar.gz` nor a tarball without the package description file. Package managers that build from the repository (straight.el, elpaca, Doom) copy only the `.el` files unless the recipe has `:files (:defaults "templates")`: every recipe in the README and any future MELPA recipe need it.

### Format changes: read the old, offer the migration

A project must never have to migrate before work goes on (user rule, 2026-11-02, docs/adr/ADR-002): every change to what Blueprint writes on disk (file location, keyword, heading layout, ID scheme) must

1. keep reading the previous format, with a test on a fixture written as the old code wrote it;
2. add a step to `blueprint-upgrade-steps` (`blueprint-upgrade.el`), in chronological order, with `:era` (the versions that wrote the old format), a read-only detector and an idempotent apply function, plus a test of both;
3. never run the migration on its own: `blueprint-project-upgrade` applies it when the user asks, after the backup.

Projects from every era back to the initial commit exist; the initial commit itself (`8b44775`) does not even load, its layout is in `blueprint-test-upgrade/pre-010-layout-step`.

## Architecture

All modules depend on `blueprint-core.el`, which provides:

- `blueprint--root` — walks up the tree to the nearest directory holding the data directory: `blueprint-directory-name` (defcustom, default `.blueprint`, may be a nested relative path) or the legacy `.blueprint` (fallback, warned once per root per session)
- `blueprint--data-dir` / `blueprint--data-path` — the data directory actually in use and paths inside it. Never hardcode `".blueprint"`: always go through these (sync writes `#+INCLUDE` paths relative to `master.org` for the same reason)
- `blueprint--org-file-regexp` — filter for `directory-files-recursively` over Org files; excludes Emacs lock files (`.#x.org`, dangling symlinks)
- `blueprint--components` — returns a hash table `{name → dir}` of all components
- `blueprint--cached-metrics` / `blueprint--invalidate-cache` — MD5-based cache for component metrics
- `blueprint--resolve-template` — three-tier template lookup (project → user → system), in the document language
- `blueprint--project-language`, `blueprint--l10n`, `blueprint--section-find` and the marker constants — see "Document language" below

`blueprint-l10n.el` is the one place of the language code (it holds no translated text). The core requires it; it calls the core functions it needs at run time (`declare-function`).

The entry point `blueprint.el` only wires the Transient menu and `require`s all modules; no logic lives there.

`blueprint-roam.el` is a soft dependency loaded with `(require 'blueprint-roam nil t)` in `blueprint.el`.

### Data flow for a typical command

1. Command reads `blueprint--root` to find `.blueprint/`
2. Calls `blueprint--components` to enumerate components; `blueprint--component-file` gives the main file (`arc42.org`, for keywords and for writing), `blueprint--component-document-paths` the files of a component that can reach the deliverable (`arc42.org`, `functional.org`, `infrastructure.org`). Anything that counts (health, dashboard, pre-delivery, lint, risks, marker lists, graph colors, daily) reads only `blueprint--document-files`: `master.org` and every file it includes with `#+INCLUDE:`, recursively, each path resolved against the including file (without `master.org`, the component documents). `blueprint--document-units` splits those files into rows (one per component, with `blueprint--component-included-paths`, then one per other file) and `blueprint--files-health-summary` counts a list of files; never build a separate file list
3. Parses files via `org-element` (never regex on Org content)
4. Uses `blueprint--cached-metrics` to avoid re-reading unchanged files
5. Writes output (`.puml`, `.svg`, buffer) to project root

### Template system (three-tier resolution)

| Priority | Path                                                                           | Purpose                 |
| -------- | ------------------------------------------------------------------------------ | ----------------------- |
| 1        | `.blueprint/templates/`                                                        | Project-local overrides |
| 2        | `~/.config/blueprint/templates/<lang>/`, then the directory itself for Italian | User defaults           |
| 3        | `templates/<lang>/` in package dir                                             | System fallback         |

`<lang>` is the document language of the project (`blueprint--project-language`). Use `blueprint--system-template-dir` and `blueprint--user-template-dirs`, never `blueprint-template-dir` directly: it is the root that holds the language folders.

Template files: `component.org`, `arc42-enterprise.org` (component.org plus the enterprise sections, chosen with `C-u` on `blueprint-add-component`), `adr.org`, `master.org`, `functional.org`, `infrastructure.org`, `glossary.org`, `references.org`, `enterprise-context.org`, `enterprise-dependencies.org`, `nfr-quality.org`, `nfr-constraints.org`, `nfr-risks.org`.

Placeholders: `{{NAME}}` (component name), `{{ID}}` (slugified, for directory names and PlantUML IDs), `{{PROJECT}}`, `{{AUTHOR}}`, `{{DATE}}`.

**Template provisioning**: When `blueprint-init` is called interactively, it checks `~/.config/blueprint/templates/<lang>/` for the language of the new project. If any template is missing (and is not in the flat legacy directory, for Italian), it copies the system templates of that language there and shows a prominent message listing every file written to the user's home. This ONLY happens interactively (not in batch/tests — uses `(called-interactively-p 'interactive)`).

### Document language (docs/adr/ADR-003-localized-templates.org)

The language of the document belongs to the project: `#+BLUEPRINT_LANGUAGE:` in `.blueprint/blueprint-version.org`, written by `blueprint-init` from `blueprint-default-language` (default `en`). No keyword means Italian (`blueprint--legacy-language`): every project created before languages existed. `blueprint--project-language` reads it; `blueprint--language` overrides it (bound by `blueprint-init`).

- A language is a folder: `templates/<lang>/` (templates), `templates/<lang>/snippets/` (skeletons inserted by the commands, `blueprint--snippet` + `blueprint--insert-aligned`, placeholders `{{X}}`), `templates/<lang>/strings.org` (short texts, `blueprint--l10n` / `blueprint--l10n-list`, looked up key by key: project, user, system, English). Languages are discovered from the folders (`blueprint--languages`). Never write a localized literal in a module: add a snippet or a key. The user interface (prompts, messages, buffers) is English and is not in the catalog.
- Sections are found with `blueprint--section-find` (and `-goto-end`, `-ensure-end`, `-bounds`, `-append-row`) by section id: first the `:BLUEPRINT_SECTION:` property, then, ignoring case, the title the templates of the project language give that section (`blueprint--section-map`) or its 0.4.x title (`blueprint--legacy-section-titles`, a frozen list: documents written since have the property, so it never grows; ADR-003 option C), outside `:noexport:` and COMMENT subtrees. Never match a heading by its literal title. A section the code creates gets the title of the project language and the property (`blueprint--section-heading`). The sections the lint expects are a fixed list of ids in `blueprint-lint.el`.
- Markers: the code writes `blueprint-marker-to-validate` / `blueprint-marker-to-review` and `[SOURCE: x]`; it reads with `blueprint--to-validate-regexp`, `blueprint--to-review-regexp`, `blueprint--source-regexp`, which also match the Italian forms.
- Every language folder has the same files, the same `:BLUEPRINT_SECTION:` set per template, the same `strings.org` keys and the same placeholders per snippet (`blueprint-test-l10n/language-folders-match`, `.../every-language-has-the-same-templates`). Change every language. Regenerate `blueprint-template-history.el` after any change to a file of `templates/`.

### Key Org keywords

`#+BLUEPRINT_DEPENDS: comp1 comp2` in a component's `arc42.org` is the sole mechanism for declaring inter-component dependencies. C4 diagram generation and the dependency graph both parse this keyword.

`#+BLUEPRINT_STATUS: in-scope|out-of-scope|tbd` (default `in-scope` when absent or unrecognized, via `blueprint--component-scope-status` in `blueprint-c4.el`) marks a component's assessment perimeter status. `blueprint-lint` warns when an in-scope component depends on an out-of-scope one; the dashboard's Scope column and out-of-scope filter (`blueprint-out-of-scope-view`, or `O` inside the dashboard buffer) read the same keyword.

## Code conventions

- All files: `;;; -*- lexical-binding: t; -*-`
- Public symbols: `blueprint-` prefix; private: `blueprint--` (double dash)
- `;;;###autoload` on all interactive public commands
- `defcustom` for all user-facing settings, group `blueprint`
- Parse Org files with `org-element`, never with regex
- Optional integrations: `(require 'feature nil t)`
- New documentation and project files are Org (`.org`), e.g. ADRs in `docs/adr/`, `CONTEXT.org`. The only Markdown exceptions are `AGENTS.md` (required by the tools that read it) and `CLAUDE.md`, which imports it

### Other autoloaded modules

`blueprint.el` also `require`s several single-purpose modules that still have no dedicated ERT suite and are not part of the test commands above:

- `blueprint-daily.el` — one-key daily triage (dashboard -> focus -> component -> document)
- `blueprint-search.el` — project-wide search via ripgrep, with a fallback
- `blueprint-wizard.el` — interactive onboarding/component-creation wizards
- `blueprint-async.el` — background processing for long-running ops (export, tangle)

Treat diffs touching these as untested until a suite is added. `blueprint-dashboard.el`, `blueprint-migrate.el`, `blueprint-watch.el`, and `blueprint-capture.el` (one regression test, not full coverage) are covered (see the Test structure table below). `blueprint-daily.el` has a few tests in `test/blueprint-test-dashboard.el` (daily candidates and document choice, loaded through `require`); `blueprint-graph.el` has node-color tests there and the pure cluster logic in `test/blueprint-test-roam.el` (the Graphviz/PlantUML file output is still untested). The modules added with the 2026-11 roadmap have their own suites: `blueprint-history.el`, `blueprint-agenda.el`, `blueprint-changelog.el` (git + ADRs), `blueprint-diff.el` (semantic component diff; always requests plain unified diffs with `--no-ext-diff`, because a `diff.external` in the user's git config would otherwise feed a format the summary cannot parse), `blueprint-preview.el` (live graph preview), `blueprint-upgrade.el` (project version, optional migrations, template status; `blueprint-template-history.el` is generated) and the JSON report in `blueprint-ci.el` (`blueprint-ci-export-json`, hash tables with string keys because an alist value that is a list is not serializable without ambiguity).

## Test structure

Tests in `test/` use ERT. The macro `blueprint-test--with-project` creates a temporary directory with a `.blueprint/` structure and removes it after each test. The project has no version file, so it is Italian; the helpers also set `blueprint-default-language` to `"it"`, because the suites were written against the Italian templates. A test of another language declares it (`blueprint-test-l10n--with-project`).

| File                           | Scope                                                                                                                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `blueprint-test-helpers.el`    | Shared macros and utilities                                                                                                                                                                      |
| `blueprint-test-core.el`       | Root, cache (incl. KIND keys), CRUD, navigation to the three documents, document files from master.org includes (nested, missing, cycles, non-exported), document rows                           |
| `blueprint-test-health.el`     | Metrics and health score (document only: master.org and its includes)                                                                                                                            |
| `blueprint-test-lint.el`       | Linter (incl. missing-file fix), project lint over every included file, missing includes                                                                                                         |
| `blueprint-test-c4.el`         | Keyword extraction, C4 generation                                                                                                                                                                |
| `blueprint-test-adr.el`        | ADR numbering and creation                                                                                                                                                                       |
| `blueprint-test-sync.el`       | Master sync and markers                                                                                                                                                                          |
| `blueprint-test-content.el`    | Glossary, references, questions (also from functional/infrastructure)                                                                                                                            |
| `blueprint-test-risks.el`      | Pattern matching (exported text of included documents only) and structural checks                                                                                                                |
| `blueprint-test-ai.el`         | Sanitization and clamping (no Ollama)                                                                                                                                                            |
| `blueprint-test-functional.el` | Incremental area/feature/entity/integration                                                                                                                                                      |
| `blueprint-test-runtime.el`    | Runtime flows and UC/sequence diagrams                                                                                                                                                           |
| `blueprint-test-nfr.el`        | Quality scenarios, constraints, risk register                                                                                                                                                    |
| `blueprint-test-delivery.el`   | Pre-delivery check and master sync, [FINDING] informative only, counts on included files only                                                                                                    |
| `blueprint-test-dashboard.el`  | Entry, status, focus mode, Owner/Tech columns, markers summed over every document, visible column titles, rows of non-component files, NOT-INCLUDED, graph colors, daily candidates              |
| `blueprint-test-migrate.el`    | Non-destructive template diff/migration, data directory rename                                                                                                                                   |
| `blueprint-test-watch.el`      | Minor mode hook install/remove, cache invalidation                                                                                                                                               |
| `blueprint-test-capture.el`    | Target of the glossary org-capture template (regression, not full coverage)                                                                                                                      |
| `blueprint-test-e2e.el`        | Full project lifecycle                                                                                                                                                                           |
| `blueprint-test-export.el`     | Duplicate title in multi-file export, headless PlantUML config, ODT style check, diagram captions, footnotes in ODT (9.16)                                                                       |
| `blueprint-test-keys.el`       | Transient and command map with the same keys, keys and commands cited in the real USAGE.org/README.org (requires `blueprint.el`)                                                                 |
| `blueprint-test-ci.el`         | JSON report for CI (`blueprint--ci-report-object`, file writing)                                                                                                                                 |
| `blueprint-test-history.el`    | Metrics history: record, dedup, line parsing, SVG chart, sync integration                                                                                                                        |
| `blueprint-test-agenda.el`     | Org agenda: TODO entries from markers, stable IDs, DEADLINE/state preserved on refresh                                                                                                           |
| `blueprint-test-changelog.el`  | Changelog: git log parsing, accepted ADR section, assembly, confirmation on existing file, real temporary repository                                                                             |
| `blueprint-test-diff.el`       | Semantic component diff: pure summary, marker deltas, e2e with a temporary git repository                                                                                                        |
| `blueprint-test-roam.el`       | Pure roam logic (clusters, similarity); database commands skipped without org-roam                                                                                                               |
| `blueprint-test-preview.el`    | Live preview: hook, debounce, buffer update, single warning without Graphviz                                                                                                                     |
| `blueprint-test-l10n.el`       | Project language, init per language, sections by property or title, English commands, legacy markers, templates per language, provisioning, upgrade steps section-properties and english-markers |
| `blueprint-test-upgrade.el`    | Project version, migration steps (a fixture for every historical format), backup, git check, template status, dashboard and CI                                                                   |

## Blueprint init: full project structure

`blueprint-init` creates more than just `.blueprint/`:

```
.blueprint/
├── components/
├── adr/                   # created empty; ADRs live in .blueprint/adr.org
└── templates/             # project overrides, initially empty
enterprise/
├── context.org            # from enterprise-context.org
└── dependencies.org       # from enterprise-dependencies.org
nfr/
├── quality-scenarios.org  # from nfr-quality.org
├── constraints.org        # from nfr-constraints.org
└── risks.org              # from nfr-risks.org
_archive/
glossary.org
references.org
master.org                 # six-part assessment deliverable
```

`.blueprint/blueprint-version.org` (Blueprint version of the layout and migrations applied, see `blueprint-upgrade.el`) is written by `blueprint-init` too, never overwritten by a re-run. Generated later, in the data directory and never included in master.org: `adr.org` (`blueprint-adr-new`), `metrics-history.org` (every `blueprint-sync`), `agenda.org` (`blueprint-agenda-refresh`), `notes.org` (org-capture).

`blueprint-add-component` creates three files per component:

- `arc42.org` — arc42 architectural view
- `functional.org` — technology-agnostic functional spec
- `infrastructure.org` — infrastructure census

Only `arc42.org` is required; the other two are created only when their templates exist (graceful degradation).

## Master sync: three sections

`blueprint-sync` manages three independent `#+INCLUDE:` sections in `master.org`:

| Marker pair                                           | File synced          |
| ----------------------------------------------------- | -------------------- |
| `@@blueprint-sync-start@@` / `@@blueprint-sync-end@@` | `arc42.org`          |
| `@@blueprint-sync-functional-start@@` / `-end@@`      | `functional.org`     |
| `@@blueprint-sync-infra-start@@` / `-end@@`           | `infrastructure.org` |

Missing marker pairs are silently skipped (backward compatible). `blueprint--generate-includes-for` only emits includes for components that actually have the file (prevents spurious includes for partially migrated projects).

## ODT styles check

`blueprint-check-odt-styles` (`blueprint-export.el`) exports master.org to ODT, then diffs every style `content.xml` references against what `#+ODT_STYLES_FILE:` (styles.xml) and content.xml's own automatic-styles define. Only a style also present in the bundled `OrgOdtStyles.xml` (`org-odt-styles-dir`) is reported, to avoid false positives from references that have no explicit definition even in a stock export (e.g. `Sect1`, part of Org's own table-of-contents scaffolding). The pure computation lives in `blueprint--check-odt-styles-missing` (no message/buffer/`kill-emacs`); `blueprint-check-odt-styles` (interactive buffer) and `blueprint-ci-check-odt-styles` (`blueprint-ci.el`, batch exit code) both build on it, the same split as `blueprint--lint-component` vs. `blueprint-lint`/`blueprint-ci-lint`. Requires `unzip`. Not part of `blueprint-ci-validate`: opt-in, since it needs a real ODT export and only applies to a project with a corporate `#+ODT_STYLES_FILE:`.

## Assessment methodology

Templates follow the method in `docs/method/method.org`:

- **Information source hierarchy**: code > tests > logs > monitoring > interviews > docs
- **Marking conventions** (English in every language; the Italian forms of 0.4.x documents are still read):
  - `[TO VALIDATE]` (`[DA VALIDARE]`) — information not yet confirmed
  - `[TO REVIEW]` (`[DA REVISIONARE]`) — produced automatically, not reviewed
  - `[FINDING]` — confirmed observation
  - `[APPROVED YYYY-MM-DD]` (`[APPROVATO ...]`) — stakeholder-approved
  - `[SOURCE: X]` (`[FONTE: X]`) — information source attribution
- **Master document structure** (six parts; Italian names in an Italian document):
  - Part 0 — Preliminaries (methodology, sources, conventions)
  - Part I — Enterprise architecture (context, dependencies)
  - Part II — Architecture by component (arc42, auto-synced)
  - Part III — Functional specifications (functional, auto-synced)
  - Part IV — Infrastructure census (infra, auto-synced)
  - Part V — Non-functional requirements and constraints (NFR, quality)

## Known bugs and fixes

Defects already fixed, kept because each one explains a constraint the code still respects.

- **`blueprint-core.el`: `blueprint-add-component` silently overwrote an existing component.** `(make-directory dir t)` signals no error when `dir` exists (the `PARENTS` flag suppresses that check). Adding a component whose slugified id collided with an existing one (the same name typed twice, or two names with the same slug, e.g. "Order Service" and "order-service") overwrote arc42.org/functional.org/infrastructure.org with the empty template: no error, no confirmation, no way to recover the lost content. **Fix**: `user-error` if the id already exists in `blueprint--components`, before any file is created. Regression tests: `blueprint-test-add-component/duplicate-name-errors`, `blueprint-test-add-component/slugify-collision-errors`.

- **Emacs lock files in recursive scans**: `.#file.org` (a dangling symlink created while `file.org` has unsaved changes) passed the `"\\.org\\'"` filter; `blueprint-list-findings`/`blueprint-list-unvalidated` failed with `file-missing`. **Fix**: `blueprint--org-file-regexp` (`blueprint-core.el`) in health, async and migrate. Regression test: `blueprint-test-list-findings/ignores-lock-files`.

- **`blueprint-lint.el`**: `blueprint--lint-component` returned an empty list when `file` was nil or missing (the `(list ...)` in the `then` branch of the `if` was discarded; `(nreverse warnings)` was always the last expression). **Fix**: `if` rewritten with the whole logic in the `else` branch.

- **`BLUEPRINT_DEPENDS` regex**: in Elisp `\\s-*` includes newlines (through the whitespace syntax class). In `"^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)"` the pattern could capture text from the next line (e.g. `"* Introduction"`), causing false positives in the isolated-dependency check. **Fix**: replaced by `[[:blank:]]*` (horizontal spaces/tabs only) in `blueprint-risks.el`, `blueprint-dashboard.el`, `blueprint-ci.el`, `blueprint-lint.el`. **Incomplete fix, later replaced**: `blueprint--org-keyword` (c4) still had `\\s-*` (an empty `#+BLUEPRINT_DEPENDS:` returned `"#+BLUEPRINT_OWNER:"`, which ended up as a dependency in the C4 and as Owner in the dashboard), and the `[[:blank:]]*` version skipped the empty line and captured the example `#+BLUEPRINT_DEPENDS: order-service notification-service` inside the `#+BEGIN_SRC org` of the template's `:noexport:` guide: every new component "depended" on two nonexistent components and `blueprint-ci-validate` failed on every new project. **Final fix**: `blueprint--org-keyword` moved to `blueprint-core.el` and rewritten with `org-element` (empty value = nil, keywords inside blocks ignored); lint, ci, dashboard and risks use it instead of regexes. Regression tests: `blueprint-test-org-keyword/empty-does-not-read-next-line`, `.../ignores-src-block-examples`, `.../fresh-component-has-no-deps`, `blueprint-test-lint/fresh-template-component-no-dangling-dep`.

- **`blueprint-rename-component` corrupted hyphenated dependencies**: the substitution in `#+BLUEPRINT_DEPENDS:` used `\\b%s\\b`, and `\\b` treats `-` as a word boundary: renaming `auth` to `identity` turned `auth-db` into `identity-db` (a nonexistent component); it also rewrote the example lines in src blocks. **Fix**: `blueprint--rename-dependency` compares whole space-separated tokens, on keywords found through `org-element`. Tests: `blueprint-test-rename-component/hyphenated-dep-untouched`, `.../src-block-example-untouched`.

- **`test/blueprint-test-e2e.el`**: unbalanced parenthesis in the `ert-deftest` `multi-component-c4`, a final `)` was missing. **Fix**: `)` added at the end of line 143.

- **ADR, single-file model**: ADRs live in one file, `adr.org` in the data directory (`.blueprint/adr.org`, through `blueprint--data-path`; the `adr/` directory created by `blueprint-init` stays empty). Each ADR is a level-1 heading `* ADR 0001: Title` with the status in the `:PROPERTIES:` drawer (`:STATUS: proposed|accepted|deprecated|superseded`). `blueprint--adr-next-number` scans the headings of `adr.org` instead of counting files. `blueprint-adr-list` reads `org-element-property :STATUS` from the drawer. The old one-file-per-ADR model is still read (ADR-002) and the upgrade offers its migration.

- **`blueprint-sync.el`, `blueprint--sync-section`**: the search for the `end-marker` started from `(point-min)` instead of the current position (after the `start-marker`). If the `end-marker` appeared before the `start-marker` (malformed file or duplicated marker), `delete-region` got inverted arguments (`start > end`) and signaled an error. **Fix**: removed the `(goto-char (point-min))` before the `end-marker` search; it now starts from the position already past the `start-marker`. Regression test: `blueprint-test-sync/sync-section-end-must-follow-start`.

- **`blueprint-export.el`, duplicate title in the multi-file export**: `#+TITLE` has `parse` behavior in `org-export-options-alist` (multiple values are concatenated). Every satellite file included in `master.org` through `#+INCLUDE` carries its own `#+TITLE` (to be readable standalone), and Org keeps it in the expanded buffer: the title of the exported document became the concatenation of all the included titles. **Fix**: `blueprint--strip-duplicate-titles`, hooked on `org-export-before-parsing-functions` when the package loads, removes every `#+TITLE` but the first after the `#+INCLUDE` expansion and before Org collects the document keywords. Being a global hook variable, it also applies to Org's native ODT export (which `blueprint-export.el` does not drive directly). Implemented with `org-element` (no regex): it only touches real keyword nodes, so a `#+TITLE:` shown as example text inside an `example`/`src` block is left alone (a common pattern in tutorial-style Org files, verified on a real config.org with `EXAMPLE` blocks). Regression test: `test/blueprint-test-export.el`.

- **`blueprint-health.el`, `blueprint--display-marker-list`**: `(blueprint--root)` was called inside `(with-current-buffer (get-buffer-create bufname) ...)`. If the buffer already existed from a previous test (with the `default-directory` of an already deleted temporary project), `blueprint--root` did not find `.blueprint/` and the function failed. **Fix**: `root` captured outside `with-current-buffer`, before switching buffer. Symptom: `blueprint-test-list-findings/finds-marker` passed alone but failed in the full suite.

- **`blueprint-questions.el`, blank line lost before the next heading**: `blueprint-add-question` inserts the new QUESTION at the position of the next heading (`next-heading`, found through `re-search-forward "^\\* "`), consuming the blank line that separated the "Open Questions" section from the next heading. The supposed related bug with headings carrying a TODO keyword or tags (`:raw-value` would not handle them) was verified as unfounded: `:raw-value` already excludes both. **Fix**: after the insert, if the next character is `*` (no blank line left), the blank line is reinserted. Regression test: `blueprint-test-questions/preserves-blank-line-before-next-heading`.

- **`blueprint-export.el`, PlantUML diagrams silently lost in the headless export**: `emacs -Q --batch` (needed for CI and reproducibility) starts with `org-confirm-babel-evaluate` set to `t` and `org-plantuml-exec-mode` set to `'jar`; without disabling the first and switching the second to the executable, every `#+begin_src plantuml` block is exported as a code listing instead of the image, with no error or warning. It works by chance in an interactive session, because the user's `init.el` already sets those values. **Fix**: macro `blueprint--with-plantuml-export`, used by all four export functions; `let` binding (not `setq`) and only while the variable still has the library default, so it never touches a user configuration. `ob-plantuml` must be required at file level, not inside the macro: otherwise `org-plantuml-exec-mode` is not yet declared special when the first `let` binds it, and you get `void-variable` or `"Defining as dynamic an already lexical var"` at run time. Regression tests: `blueprint-test-export/plantuml-export-*`.

- **`blueprint-export.el`, diagram captions lost in the export**: Babel replaces a `:exports results` block (the ob-plantuml default) with its `#+RESULTS:` and deletes the block's affiliated keywords, `#+CAPTION:` included. No export hook falls between the `#+INCLUDE:` expansion and Babel. **Fix**: `blueprint--move-result-captions`, an `:around` advice on `org-babel-exp-process-buffer`: before Babel, a sentinel line after the results (or after the block, if it has none); after Babel, `#+CAPTION:`/`#+NAME:`/`#+ATTR_*:` go on the `#+RESULTS:` paragraph that precedes the sentinel. It also covers blocks evaluated for the first time during the export. Tests: `blueprint-test-export/caption-*`, `.../odt-caption-reaches-content-xml`.

- **`blueprint-sync.el`, spurious blank line at every sync**: `blueprint--sync-section` did `(insert "\n" content "\n")`, but the insertion point (`(1+ start)`) is already at the start of the line right after the start marker: the leading `\n` added an extra blank line between marker and synced content at every `blueprint-sync`. **Fix**: removed the redundant leading `\n`. Regression test: `blueprint-test-sync/sync-section-no-spurious-blank-line`.

- **`templates/nfr-risks.org`, placeholder row**: the template had `| R-001 | |...|` as an example, so `blueprint--nfr-next-risk-id` returned `R-002` instead of `R-001` after `blueprint-init`. **Fix**: example moved to a separate `:noexport:` guide section; the real table starts empty. Pattern applied to every template.

- **Template `:noexport:` pattern**: every template has a `:noexport:` compilation guide with realistic data (invented project "PiattaformaPagamenti"). `:noexport:` sections are visible in Emacs and when reviewing the raw Org file, but excluded from the HTML/PDF export. The code never reaches them, because it looks for specific sections (e.g. the risk register) that come after the guide.

- **`blueprint-health.el`, SVG gauge never visible in Emacs**: `blueprint-health-svg` opened `health.svg` with `find-file`, i.e. in `image-mode`. With Emacs built with ImageMagick, `image--imagemagick-wanted-p` hands every file to ImageMagick (except the extensions in `imagemagick-types-inhibit`), and the ImageMagick security policy of many distributions forbids SVG: an empty box was left. The file also did not declare `xmlns` (browsers and LibreOffice do not recognize it as SVG) and had a transparent background with black strokes (invisible with a dark theme). **Fix**: the file is still written, but shown in the `*Blueprint Health*` buffer with `create-image` of type `svg` (native librsvg); `blueprint--health-svg-string` produces a document with namespace and white background. Verified with a screenshot under Xvfb (a PGTK build needs `env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:N`, otherwise the window opens on the Wayland session). Tests: `blueprint-test-health-svg/*`.

- **Read-only copies from a read-only installation (CI red since September)**: `copy-file` keeps the permissions of the source. With Org or Blueprint installed in a read-only store (in CI `purcell/setup-emacs` uses Nix, files 0444) the copies stayed 0444: `blueprint-test--odt-styles-copy` opened `styles.xml` in a read-only buffer and `odt-styles-check-detects-missing-style` failed on every version (it passed locally, files 0644). The same hit the package: `blueprint--provision-user-templates` and `blueprint-template-migrate` produced "editable" templates that could not be written. **Fix**: `blueprint--copy-file-writable` (`blueprint-core.el`) adds the owner write bit after the copy; the test fixture writes the file from a buffer. The CI matrix now has `fail-fast: false`, because a failure on one version cancelled the others. To try Emacs 29 locally: `docker run --rm -v "$PWD":/src:ro silex/emacs:29.1 ...`. Tests: `blueprint-test-migrate/copies-are-writable-from-read-only-source`, `.../provisioned-user-templates-writable`.

- **Component templates without a skeleton**: `component.org`, `functional.org` and `infrastructure.org` had, outside the guide, placeholder prose, empty tables, example PlantUML diagrams and one `[DA VALIDARE]` per section: all exported text, so the lint never reported a component that was never filled in. Now the body has only headings and `<<{{ID}}-...>>` anchors; section descriptions and models (tables, diagrams) are in the `:noexport:` guide. The guide's PlantUML blocks have `:eval never`: Babel also evaluates blocks in `:noexport:` subtrees (verified: without it, every export generates the svgs). The lint does not count anchor-only lines as content. Not touched: the other templates (master, enterprise, nfr, glossary, references, adr) and the skeleton that the `blueprint-functional-add-*` / `blueprint-runtime-add-*` commands insert for the sections they create.

- **0.3.0 review (red CI and defects of the new modules)**: the byte-compile failed because `blueprint-sync.el` read `blueprint-history-on-sync` through a soft `require` (variable void when `blueprint-history` was not loaded) and `blueprint-roam.el` called `blueprint--dependency-clusters` without `require 'blueprint-graph`; both are now plain `require`s (no cycle: history -> health -> core). The test `blueprint-test-preview/update-refreshes-preview-buffer` needs `dot`: the workflow installs Graphviz and the test has `skip-unless`. Other defects fixed, with regression tests: `;;;###autoload` moved by mistake onto the templates `defconst` (`blueprint-add-component` no longer autoloaded); the agenda's `:ORIGIN:` relative to the root but written in a file of the data directory (broken link) and IDs based on the absolute path; the changelog listed the template's `:noexport:` example ADR; `json-serialize` writes `nil` as `{}` (use `:null`/`:false`); in org-roam `links.source` is a node ID, not a file; the preview timer resolved the root from the current buffer when it fired; `blueprint-component-diff` without a revision ignored staged changes and passed `""` to git; `blueprint-roam-clusters` failed on the second call (read-only buffer); the lifecycle lint counted the FIXMEs of arc42.org only; the state of questions came from the line prefix and not from the marker; `blueprint-glossary-add` on an empty section did `goto-char nil`.

- **Second pass on 0.3.0 (declared but not working)**: component ids are hyphenated slugs and an unquoted DOT id only allows letters, digits and `_`: `dot` exited with a syntax error and the SVG dashboard, the preview and the Graphviz backend produced nothing. **Fix**: `blueprint--dot-id` (quotes) and `blueprint--dot-render` (error if `dot` fails), in `blueprint-core.el`. `blueprint-agenda` used `org-agenda-list`, which only shows dated entries: it is now a block view agenda + `alltodo` with `org-agenda-files` in the command settings (they also apply to `g`). Org reads as planning only the line right after the heading: DEADLINE/SCHEDULED/CLOSED go on a single line (`blueprint--agenda-planning-line`). org-roam schema: the `tags` table has `node-id`, not `node`; `links.source` is a node ID; the file node has `level` 0. The diff parser reads content only inside hunks (`@@`). Tests: `blueprint-test-graph/dot-ids-are-quoted`, `blueprint-test-agenda/agenda-view-lists-undated-entries`, `.../planning-line-survives-two-refreshes`, `blueprint-test-roam/similar-uses-roam-schema`, `blueprint-test-diff/summary-only-hunk-content`, `.../untracked-files-shown`, `blueprint-test-delete-component/first-component-no-stray-break`.

- **`blueprint.el`, autoloads failing before Transient (0.5.0)**: a bare `;;;###autoload` on `transient-define-prefix` copies the whole form into the autoloads file; a package manager that loads the autoloads before Transient (package.el, straight, Doom) gets `void-function transient-define-prefix`. **Fix**: `;;;###autoload (autoload 'blueprint-menu "blueprint" nil t)`, the form Magit uses. Any new Transient prefix needs the same. Test: `blueprint-test-keys/menu-autoload-needs-no-transient`.

## Health scoring

The score covers the document only (`blueprint--document-files`: master.org and everything it includes). Markers add weighted penalty points P (`blueprint--health-weights`):

- **Technical markers**: `QUESTION` = 3, `TBD` = 2, `FIXME` = 4
- **Methodology markers**: `[TO VALIDATE]` = 1, `[TO REVIEW]` = 1 (each with its Italian legacy form), `[FINDING]` = 0 (a result the assessment delivers, still counted by the metrics and the lists)

P is set against the W words of exported text of the same files: `score = round(100 * W / (W + N * P))` with N = `blueprint-health-words-per-point` (default 100), 100 when P is 0 (`blueprint--health-score-from`).

Only markers in exported text count: `blueprint--uncounted-regions` (`blueprint-core.el`) excludes export-excluded subtrees (`:noexport:`, `#+EXCLUDE_TAGS:`), COMMENT subtrees, src/example/export/comment blocks, comments, verbatim/code objects and property drawers; matching is case-sensitive. Use `blueprint--count-file-markers` / `blueprint--marker-positions` for any new marker scan instead of `count-matches` on raw text. Keywords (`#+STATUS: [TO VALIDATE]`) still count. The lint "no content" check ignores lines in non-exported subtrees (`blueprint--non-exported-subtrees`) and in property drawers but, unlike marker counting, still treats src blocks and verbatim as content.

Per-file counts and words are cached via `blueprint--cached-metrics` under the kind `document-stats` (keys are `(FILE . KIND)`, so they never collide with the technical counts cached for arc42.org).

`blueprint-list-findings` and `blueprint-list-unvalidated` scan the document files (master.org and its includes) and display results in a read-only buffer. `blueprint--display-marker-list` captures `(blueprint--root)` **before** `(with-current-buffer ...)` to avoid stale `default-directory` from pre-existing result buffers (isolation-critical for tests).
