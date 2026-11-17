;;; blueprint-references.el --- Reference tracking for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Tracks references in references.org, routed by type into the
;; documents or interviews section the template already defines (see
;; templates/<lang>/references.org).  The other two template sections
;; (systems and tools, environments analyzed) stay manually compiled
;; -- no command targets them.

;;; Code:

(require 'blueprint-core)

(defun blueprint--references-next-id (prefix section)
  "Return the next PREFIX-NN reference ID based on existing entries.
Scans only within SECTION (a section id such as
`references-documents', see `blueprint--section-find'), not the
whole file: the :noexport: compilation guide above it shows D-01/D-02
and I-01/I-02 as worked examples, and without this boundary a fresh
project's first real reference would collide with them (the same
class of bug `blueprint--nfr-next-risk-id' had -- see its docstring)."
  (let ((file (blueprint--references-file))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((bounds (blueprint--section-bounds section 1)))
          (when bounds
            (goto-char (car bounds))
            (while (re-search-forward
                    (format "| %s-\\([0-9]+\\) " (regexp-quote prefix)) (cdr bounds) t)
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
TYPE is one of \"interview\" (routed to the interviews table) or
\"document\", \"codebase\", \"ticket\", \"monitoring\" (routed to the
documents table, where TYPE becomes that table's own type column).
Columns this command has no dedicated argument for (role for an
interview, author / owner for a document) are filled with
[TO VALIDATE] rather than left blank, so they surface in
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
The row goes to the interviews table for TYPE \"interview\" and to
the documents table otherwise, with the next I-NN/D-NN id.  DATE
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
          (let ((id (blueprint--references-next-id "I" 'references-interviews)))
            (blueprint--section-append-row
             'references-interviews
             (format "| %s | %s | %s | %s | %s | |\n"
                     id (funcall cell title) blueprint-marker-to-validate
                     date (funcall cell notes))))
        (let ((id (blueprint--references-next-id "D" 'references-documents)))
          (blueprint--section-append-row
           'references-documents
           (format "| %s | %s | %s | %s | %s | %s |\n"
                   id (funcall cell title) blueprint-marker-to-validate
                   date (funcall cell type) (funcall cell notes)))))
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
