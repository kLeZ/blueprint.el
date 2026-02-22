;;; blueprint.el --- Text-first architectural assessment toolkit  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.4"))
;; Keywords: tools, architecture, documentation
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Blueprint Ultra is a text-first architectural assessment toolkit for
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
;;   - Project initialization and component management
;;   - C4 container diagram generation (PlantUML) from declared dependencies
;;   - Health scoring with SVG gauge visualization
;;   - Three-tier template system (project > user > system) with diff
;;     and non-destructive migration
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

(require 'transient)

;;;###autoload
(transient-define-prefix blueprint-menu ()
  "Blueprint Ultra main menu."
  [["Architecture"
    ("C" "generate C4" blueprint-generate-c4)]
   ["Quality"
    ("H" "health svg" blueprint-health-svg)]
   ["Templates"
    ("D" "diff" blueprint-template-diff)
    ("M" "migrate" blueprint-template-migrate)]
   ["Project"
    ("I" "init" blueprint-init)
    ("A" "add component" blueprint-add-component)]])

;;;###autoload
(defvar blueprint-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C") #'blueprint-generate-c4)
    (define-key map (kbd "H") #'blueprint-health-svg)
    (define-key map (kbd "D") #'blueprint-template-diff)
    (define-key map (kbd "M") #'blueprint-template-migrate)
    (define-key map (kbd "I") #'blueprint-init)
    (define-key map (kbd "A") #'blueprint-add-component)
    map)
  "Keymap for Blueprint commands (non-transient).
Bind this to a prefix key if you prefer plain keybindings over Transient:
  (global-set-key (kbd \"C-c b\") blueprint-command-map)")

;; Suggested binding — uncomment or add to your init file:
;;   (global-set-key (kbd "C-c b") #'blueprint-menu)

(provide 'blueprint)
;;; blueprint.el ends here
