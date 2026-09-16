;;; blueprint-glossary.el --- Glossary management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Structured glossary stored in glossary.org at the project root
;; (the same file `blueprint-init' creates and `master.org' includes).
;; Each term is an Org heading with properties for source attribution.

;;; Code:

(require 'blueprint-core)

(defun blueprint--glossary-file ()
  "Return the path to the glossary file.
This is `glossary.org' at the project root -- the same file
`blueprint-init' creates from the glossary.org template and the same
file `master.org' pulls in via `#+INCLUDE:' (see the Part 0 section).
Not under `.blueprint/': that directory holds per-component and
per-ADR data, not project-level deliverable files."
  (expand-file-name "glossary.org" (blueprint--root)))

(defun blueprint--ensure-glossary ()
  "Create the glossary file from the template if it does not exist.
Uses the real glossary.org template (the same one `blueprint-init'
uses) rather than a bare stub, so a glossary lazily created by the
first `blueprint-glossary-add' still has the sections and guidance a
`blueprint-init'-created one has."
  (let ((file (blueprint--glossary-file)))
    (blueprint--init-file
     file "glossary.org" `(("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))))
    file))

;;;###autoload
(defun blueprint-glossary-add (term definition source)
  "Add TERM with DEFINITION and SOURCE to the project glossary."
  (interactive "sTerm: \nsDefinition: \nsSource: ")
  (let ((file (blueprint--ensure-glossary)))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "* %s\n:PROPERTIES:\n:SOURCE: %s\n:END:\n%s\n"
                      term source definition))
      (save-buffer))
    (message "Added glossary term: %s" term)))

;;;###autoload
(defun blueprint-glossary-list ()
  "Open the project glossary file."
  (interactive)
  (find-file (blueprint--ensure-glossary)))

;;;###autoload
(defun blueprint-glossary-lookup (term)
  "Search for TERM in the glossary and display its definition."
  (interactive "sLookup term: ")
  (let ((file (blueprint--glossary-file)))
    (unless (file-exists-p file)
      (user-error "No glossary file found"))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (if (re-search-forward (format "^\\* %s" (regexp-quote term)) nil t)
          (let ((start (line-beginning-position))
                (end (or (save-excursion
                           (when (re-search-forward "^\\* " nil t)
                             (line-beginning-position)))
                         (point-max))))
            (message "%s" (string-trim
                           (buffer-substring-no-properties start end))))
        (message "Term \"%s\" not found in glossary" term)))))

(provide 'blueprint-glossary)
;;; blueprint-glossary.el ends here
