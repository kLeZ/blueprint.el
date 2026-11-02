;;; blueprint-references.el --- Reference tracking for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Tracks references in references.org, routed by type into the
;; "Documenti" or "Interviste" section the template already defines
;; (see templates/references.org).  "Sistemi e strumenti" and
;; "Ambienti analizzati", the other two template sections, stay
;; manually compiled -- no command targets them.

;;; Code:

(require 'blueprint-core)

(defun blueprint--references-insert-row-in-section (section-heading row)
  "Append ROW after the last org-table line under SECTION-HEADING.
Works on the current buffer.  If the section is absent, appends both
the heading and the row at the end of the buffer.  Mirrors
`blueprint--nfr-insert-row-in-section' in blueprint-nfr.el.

SECTION-HEADING is matched anchored to the start of a line: the
:noexport: compilation guide in references.org has subheadings like
\"** Documenti (esempio)\", and an unanchored search for \"* Documenti\"
matches inside that text too (starting at its second `*'), finding
the guide's example section instead of the real one."
  (goto-char (point-min))
  (let ((last-pipe-pos nil)
        (heading-re (concat "^" (regexp-quote section-heading))))
    (when (re-search-forward heading-re nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\*" nil t)
                               (match-beginning 0)
                             (point-max)))))
        (while (re-search-forward "^|" section-end t)
          (setq last-pipe-pos (line-end-position)))))
    (if last-pipe-pos
        (progn (goto-char last-pipe-pos) (insert "\n" row))
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert row))))

(defun blueprint--references-next-id (prefix section-heading)
  "Return the next PREFIX-NN reference ID based on existing entries.
Scans only within SECTION-HEADING (e.g. \"* Documenti\"), not the
whole file: the :noexport: compilation guide above it shows D-01/D-02
and I-01/I-02 as worked examples, and without this boundary a fresh
project's first real reference would collide with them (the same
class of bug `blueprint--nfr-next-risk-id' had -- see its docstring)."
  (let ((file (blueprint--references-file))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward (concat "^" (regexp-quote section-heading)) nil t)
          (let ((section-end (save-excursion
                               (if (re-search-forward "^\\*" nil t)
                                   (match-beginning 0)
                                 (point-max)))))
            (while (re-search-forward
                    (format "| %s-\\([0-9]+\\) " (regexp-quote prefix)) section-end t)
              (let ((n (string-to-number (match-string 1))))
                (when (> n max-num) (setq max-num n))))))))
    (format "%s-%02d" prefix (1+ max-num))))

(defun blueprint--references-file ()
  "Return the path to the references file.
This is `references.org' at the project root -- the same file
`blueprint-init' creates from the references.org template and the
same file `master.org' pulls in via `#+INCLUDE:'.  Not under
`.blueprint/': that directory holds per-component and per-ADR data,
not project-level deliverable files."
  (expand-file-name "references.org" (blueprint--root)))

(defun blueprint--ensure-references ()
  "Create the references file from the template if it does not exist.
Uses the real references.org template (the same one `blueprint-init'
uses) rather than a bare stub, so a references file lazily created by
the first `blueprint-reference-add' still has the sections and
guidance a `blueprint-init'-created one has."
  (let ((file (blueprint--references-file)))
    (blueprint--init-file
     file "references.org" `(("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))))
    file))

;;;###autoload
(defun blueprint-reference-add (title type notes)
  "Add a reference with TITLE, TYPE, and NOTES.
TYPE is one of \"interview\" (routed to the `* Interviste' table) or
\"document\", \"codebase\", \"ticket\", \"monitoring\" (routed to the
`* Documenti' table, where TYPE becomes that table's own \"Tipo\"
column).  Columns this command has no dedicated argument for (Ruolo
for an interview, Autore / Owner for a document) are filled with
[DA VALIDARE] rather than left blank, so they surface in
`blueprint-list-unvalidated' like any other pending detail."
  (interactive
   (list (read-string "Reference title: ")
         (completing-read
          "Type: " '("document" "interview" "codebase" "ticket" "monitoring") nil t)
         (read-string "Notes: ")))
  (blueprint--references-add-row title type notes)
  (message "Added reference: %s" title))

(defun blueprint--references-add-row (title type notes &optional date)
  "Add the reference TITLE of TYPE with NOTES to references.org.
The row goes to the `* Interviste' table for TYPE \"interview\" and to
the `* Documenti' table otherwise, with the next I-NN/D-NN id.  DATE
defaults to today: the migration of the older formats passes the
date the reference was recorded with."
  (let ((file (blueprint--ensure-references))
        (date (or date (format-time-string "%Y-%m-%d")))
        (cell (lambda (text)
                ;; A cell cannot hold a newline or a bar.
                (string-trim
                 (replace-regexp-in-string
                  "[ \t]*\n[ \t]*" " "
                  (replace-regexp-in-string "|" "/" (or text "")))))))
    (with-current-buffer (find-file-noselect file)
      (if (string= type "interview")
          (let ((id (blueprint--references-next-id "I" "* Interviste")))
            (blueprint--references-insert-row-in-section
             "* Interviste"
             (format "| %s | %s | [DA VALIDARE] | %s | %s | |\n"
                     id (funcall cell title) date (funcall cell notes))))
        (let ((id (blueprint--references-next-id "D" "* Documenti")))
          (blueprint--references-insert-row-in-section
           "* Documenti"
           (format "| %s | %s | [DA VALIDARE] | %s | %s | %s |\n"
                   id (funcall cell title) date (funcall cell type)
                   (funcall cell notes)))))
      (save-buffer))
    file))

;;;###autoload
(defun blueprint-reference-list ()
  "Open the project references file.
When the references file older versions wrote inside the data
directory still exists (until 2026-09 `blueprint-reference-add' wrote
there, a file master.org never included), says so: its entries are
still there to read, and `blueprint-project-upgrade' moves them into
the references file."
  (interactive)
  (find-file (blueprint--ensure-references))
  (let ((orphan (blueprint--data-path "references.org")))
    (when (and (file-exists-p orphan)
               (not (file-equal-p orphan (blueprint--references-file))))
      (message "Also %s holds references (previous format): blueprint-project-upgrade moves them here"
               (file-relative-name orphan (blueprint--root))))))

(provide 'blueprint-references)
;;; blueprint-references.el ends here
