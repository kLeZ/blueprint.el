;;; blueprint.el --- Text-first architectural assessment toolkit  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.4"))
;; Keywords: tools, architecture, documentation
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Blueprint Ultra is a text-first architectural assessment toolkit for Emacs.
;; It provides tools for managing software architecture documentation,
;; generating C4 diagrams, assessing component health, and managing templates.
;;
;; Main entry point is the transient menu bound to `C-c b'.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)
(require 'blueprint-migrate)

(require 'transient)

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

(global-set-key (kbd "C-c b") #'blueprint-menu)

(provide 'blueprint)
;;; blueprint.el ends here
