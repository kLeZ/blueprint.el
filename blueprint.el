;;; blueprint.el --- Text-first architectural assessment toolkit  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; Version: 0.4.0
;; Package-Requires: ((emacs "29.1") (transient "0.4"))
;; Keywords: tools, architecture, documentation
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Blueprint is a text-first architectural assessment toolkit for
;; GNU Emacs.  It grew out of a Python CLI scaffolder and was rewritten
;; in Emacs Lisp to take full advantage of Org mode, the org-element AST,
;; and Transient menus.
;;
;; The package helps software architects manage component-based
;; documentation following the Arc42 methodology.  Each component lives
;; in its own directory under `.blueprint/components/' with an `arc42.org'
;; file that declares dependencies via `#+BLUEPRINT_DEPENDS:' keywords.
;;
;; Core capabilities:
;;   - Project initialization, component CRUD, and wizard onboarding
;;   - C4 container diagram and dependency graph generation (PlantUML/Graphviz)
;;   - Health scoring with SVG gauge visualization
;;   - Dashboard buffer (Magit-style) with focus mode
;;   - Three-tier template system with diff and non-destructive migration
;;   - Glossary, references, and open questions management
;;   - Master file sync with #+INCLUDE: directives
;;   - Linter with CI/headless support
;;   - Org-native export (PDF, ODT, HTML, DOCX); interactive dispatch to
;;     pick a backend/template at runtime instead of a fixed default
;;   - Auto-tangle and watch mode
;;   - Rule-based risk suggestions
;;   - AI-assisted snippets via Ollama (optional)
;;   - Quick capture, daily workflow, ripgrep search
;;   - ADR management
;;   - org-roam integration (optional)
;;
;; Usage:
;;   M-x blueprint-init   to create a new project
;;   M-x blueprint-menu   to open the Transient command menu
;;
;; Suggested keybinding:
;;   (global-set-key (kbd "C-c b") #'blueprint-menu)
;;
;; See the README for full documentation and the design rationale.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)
(require 'blueprint-migrate)
(require 'blueprint-adr)
(require 'blueprint-lint)
(require 'blueprint-dashboard)
(require 'blueprint-questions)
(require 'blueprint-glossary)
(require 'blueprint-references)
(require 'blueprint-sync)
(require 'blueprint-search)
(require 'blueprint-export)
(require 'blueprint-async)
(require 'blueprint-watch)
(require 'blueprint-graph)
(require 'blueprint-wizard)
(require 'blueprint-capture)
(require 'blueprint-daily)
(require 'blueprint-risks)
(require 'blueprint-ai)
(require 'blueprint-ci)
(require 'blueprint-functional)
(require 'blueprint-runtime)
(require 'blueprint-nfr)
(require 'blueprint-delivery)
(require 'blueprint-history)
(require 'blueprint-agenda)
(require 'blueprint-changelog)
(require 'blueprint-diff)
(require 'blueprint-preview)
(require 'blueprint-upgrade)

;; Optional integrations (soft dependencies)
(require 'blueprint-roam nil t)

(require 'transient)

;;;###autoload
(transient-define-prefix blueprint-menu ()
  "Blueprint main menu."
  [["Project"
    ("I" "init" blueprint-init)
    ("W" "wizard init" blueprint-wizard-init)
    ("A" "add component" blueprint-add-component)
    ("w" "wizard component" blueprint-wizard-component)
    ("R" "rename component" blueprint-rename-component)
    ("X" "delete component" blueprint-delete-component)
    ("l" "list components" blueprint-list-components)
    ("j" "visit document" blueprint-visit-component)
    ("J" "generate changelog" blueprint-changelog-generate)]
   ["Architecture"
    ("C" "generate C4" blueprint-generate-c4)
    ("V" "enterprise C4" blueprint-generate-enterprise-c4)
    ("G" "dependency graph (puml/dot)" blueprint-dependency-graph)
    ("h" "health-colored graph (SVG)" blueprint-dashboard-svg)
    ("S" "sync master" blueprint-sync)]
   ["Quality"
    ("H" "health svg" blueprint-health-svg)
    ("L" "lint" blueprint-lint)
    ("s" "suggest risks" blueprint-suggest-risks-all)
    ("d" "pre-delivery check" blueprint-pre-delivery-check)
    ("g" "list findings" blueprint-list-findings)
    ("u" "list unvalidated" blueprint-list-unvalidated)
    ("U" "org-agenda triage" blueprint-agenda)]
   ["Dashboard"
    ("B" "dashboard" blueprint-dashboard)
    ("F" "focus mode" blueprint-focus)
    ("o" "out-of-scope view" blueprint-out-of-scope-view)
    ("x" "metrics history" blueprint-metrics-history)
    ("." "daily workflow" blueprint-daily)]]
  [["Content"
    ("Q" "add question" blueprint-add-question)
    ("q" "list questions" blueprint-list-questions)
    ("Y" "glossary" blueprint-glossary-list)
    ("y" "add glossary term" blueprint-glossary-add)
    ("Z" "references" blueprint-reference-list)
    ("z" "add reference" blueprint-reference-add)]
   ["Templates"
    ("D" "diff" blueprint-template-diff)
    ("M" "migrate" blueprint-template-migrate)
    ("m" "migrate data directory" blueprint-migrate-directory)
    ("^" "upgrade project" blueprint-project-upgrade)]
   ["Export"
    ("E" "export (default backend)" blueprint-export)
    ("P" "export PDF" blueprint-export-pdf)
    ("O" "export ODT" blueprint-export-odt)
    ("v" "export... (choose format)" blueprint-export-dispatch)
    ("k" "check ODT styles" blueprint-check-odt-styles)
    ("T" "async tangle" blueprint-async-tangle)]
   ["Search & ADR"
    ("/" "search" blueprint-search)
    ("N" "new ADR" blueprint-adr-new)
    ("n" "list ADRs" blueprint-adr-list)
    ("K" "capture" blueprint-capture)]]
  [["Functional"
    ("a" "add area" blueprint-functional-add-area)
    ("f" "add feature" blueprint-functional-add-feature)
    ("e" "add entity" blueprint-functional-add-entity)
    ("i" "add integration" blueprint-functional-add-integration)]
   ["Runtime"
    ("r" "add flow" blueprint-runtime-add-flow)
    ("b" "add business process" blueprint-runtime-add-process)]
   ["NFR"
    ("p" "quality scenario" blueprint-nfr-add-quality-scenario)
    ("c" "constraint" blueprint-nfr-add-constraint)
    ("t" "risk entry" blueprint-nfr-add-risk)]])

;;;###autoload
(defvar blueprint-command-map
  (let ((map (make-sparse-keymap)))
    ;; Same keys as `blueprint-menu', group by group, so that one key
    ;; table documents both (test/blueprint-test-keys.el checks it).
    ;; Project
    (define-key map (kbd "I") #'blueprint-init)
    (define-key map (kbd "W") #'blueprint-wizard-init)
    (define-key map (kbd "A") #'blueprint-add-component)
    (define-key map (kbd "w") #'blueprint-wizard-component)
    (define-key map (kbd "R") #'blueprint-rename-component)
    (define-key map (kbd "X") #'blueprint-delete-component)
    (define-key map (kbd "l") #'blueprint-list-components)
    (define-key map (kbd "j") #'blueprint-visit-component)
    (define-key map (kbd "J") #'blueprint-changelog-generate)
    ;; Architecture
    (define-key map (kbd "C") #'blueprint-generate-c4)
    (define-key map (kbd "V") #'blueprint-generate-enterprise-c4)
    (define-key map (kbd "G") #'blueprint-dependency-graph)
    (define-key map (kbd "h") #'blueprint-dashboard-svg)
    (define-key map (kbd "S") #'blueprint-sync)
    ;; Quality
    (define-key map (kbd "H") #'blueprint-health-svg)
    (define-key map (kbd "L") #'blueprint-lint)
    (define-key map (kbd "s") #'blueprint-suggest-risks-all)
    (define-key map (kbd "d") #'blueprint-pre-delivery-check)
    (define-key map (kbd "g") #'blueprint-list-findings)
    (define-key map (kbd "u") #'blueprint-list-unvalidated)
    (define-key map (kbd "U") #'blueprint-agenda)
    ;; Dashboard
    (define-key map (kbd "B") #'blueprint-dashboard)
    (define-key map (kbd "F") #'blueprint-focus)
    (define-key map (kbd "o") #'blueprint-out-of-scope-view)
    (define-key map (kbd "x") #'blueprint-metrics-history)
    (define-key map (kbd ".") #'blueprint-daily)
    ;; Content
    (define-key map (kbd "Q") #'blueprint-add-question)
    (define-key map (kbd "q") #'blueprint-list-questions)
    (define-key map (kbd "Y") #'blueprint-glossary-list)
    (define-key map (kbd "y") #'blueprint-glossary-add)
    (define-key map (kbd "Z") #'blueprint-reference-list)
    (define-key map (kbd "z") #'blueprint-reference-add)
    ;; Templates
    (define-key map (kbd "D") #'blueprint-template-diff)
    (define-key map (kbd "M") #'blueprint-template-migrate)
    (define-key map (kbd "m") #'blueprint-migrate-directory)
    (define-key map (kbd "^") #'blueprint-project-upgrade)
    ;; Export
    (define-key map (kbd "E") #'blueprint-export)
    (define-key map (kbd "P") #'blueprint-export-pdf)
    (define-key map (kbd "O") #'blueprint-export-odt)
    (define-key map (kbd "v") #'blueprint-export-dispatch)
    (define-key map (kbd "k") #'blueprint-check-odt-styles)
    (define-key map (kbd "T") #'blueprint-async-tangle)
    ;; Search & ADR
    (define-key map (kbd "/") #'blueprint-search)
    (define-key map (kbd "N") #'blueprint-adr-new)
    (define-key map (kbd "n") #'blueprint-adr-list)
    (define-key map (kbd "K") #'blueprint-capture)
    ;; Functional
    (define-key map (kbd "a") #'blueprint-functional-add-area)
    (define-key map (kbd "f") #'blueprint-functional-add-feature)
    (define-key map (kbd "e") #'blueprint-functional-add-entity)
    (define-key map (kbd "i") #'blueprint-functional-add-integration)
    ;; Runtime
    (define-key map (kbd "r") #'blueprint-runtime-add-flow)
    (define-key map (kbd "b") #'blueprint-runtime-add-process)
    ;; NFR
    (define-key map (kbd "p") #'blueprint-nfr-add-quality-scenario)
    (define-key map (kbd "c") #'blueprint-nfr-add-constraint)
    (define-key map (kbd "t") #'blueprint-nfr-add-risk)
    map)
  "Keymap for Blueprint commands (non-transient).
It binds the same keys to the same commands as `blueprint-menu'.
Bind this to a prefix key if you prefer plain keybindings over Transient:
  (global-set-key (kbd \"C-c b\") blueprint-command-map)")

;; Suggested binding — uncomment or add to your init file:
;;   (global-set-key (kbd "C-c b") #'blueprint-menu)

(provide 'blueprint)
;;; blueprint.el ends here
