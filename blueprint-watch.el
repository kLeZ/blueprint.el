;;; blueprint-watch.el --- Auto-tangle and watch mode for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Minor modes for automatic actions on save: auto-tangle runs
;; `org-babel-tangle' on Blueprint .org files; watch mode invalidates
;; cache and optionally re-syncs the master file and regenerates C4.

;;; Code:

(require 'blueprint-core)

(declare-function blueprint-sync "blueprint-sync" ())
(declare-function blueprint-generate-c4 "blueprint-c4" ())

(defcustom blueprint-watch-auto-sync nil
  "When non-nil, watch mode re-syncs master.org on save."
  :type 'boolean
  :group 'blueprint)

(defcustom blueprint-watch-auto-c4 nil
  "When non-nil, watch mode regenerates C4 diagram on save."
  :type 'boolean
  :group 'blueprint)

(defun blueprint--in-project-p ()
  "Return non-nil if the current buffer's file is inside a Blueprint project."
  (and buffer-file-name
       (ignore-errors (blueprint--root))
       (string-prefix-p
        (blueprint--data-dir)
        (expand-file-name buffer-file-name))))

(defun blueprint--auto-tangle-hook ()
  "Hook to auto-tangle the current Org file if inside a Blueprint project."
  (when (and (blueprint--in-project-p)
             (string-suffix-p ".org" buffer-file-name))
    (org-babel-tangle)))

(defun blueprint--watch-hook ()
  "Hook to run watch-mode actions after saving a Blueprint file."
  (when (blueprint--in-project-p)
    (blueprint--invalidate-cache buffer-file-name)
    (when blueprint-watch-auto-sync
      (require 'blueprint-sync)
      (blueprint-sync))
    (when blueprint-watch-auto-c4
      (require 'blueprint-c4)
      (blueprint-generate-c4))))

;;;###autoload
(define-minor-mode blueprint-auto-tangle-mode
  "Minor mode to auto-tangle Blueprint Org files on save."
  :lighter " BpTangle"
  :global t
  :group 'blueprint
  (if blueprint-auto-tangle-mode
      (add-hook 'after-save-hook #'blueprint--auto-tangle-hook)
    (remove-hook 'after-save-hook #'blueprint--auto-tangle-hook)))

;;;###autoload
(define-minor-mode blueprint-watch-mode
  "Minor mode for automatic actions on save in Blueprint projects.
Invalidates metrics cache, and optionally re-syncs master.org and
regenerates C4 diagrams."
  :lighter " BpWatch"
  :global t
  :group 'blueprint
  (if blueprint-watch-mode
      (add-hook 'after-save-hook #'blueprint--watch-hook)
    (remove-hook 'after-save-hook #'blueprint--watch-hook)))

(provide 'blueprint-watch)
;;; blueprint-watch.el ends here
