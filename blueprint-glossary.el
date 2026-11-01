;;; blueprint-glossary.el --- Glossary management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Structured glossary stored in glossary.org at the project root
;; (the same file `blueprint-init' creates and `master.org' includes).
;;
;; A term is added as a level-2 heading at the end of one of the
;; sections the template defines ("Termini di dominio", "Termini
;; tecnici con uso specifico", "Acronimi e abbreviazioni"), in the
;; format of the template itself: the definition followed by a
;; /Fonte: .../ line.  Entries written by older Blueprint versions (level-1
;; headings with a :PROPERTIES: drawer appended at the end of the
;; file) keep working: `blueprint-glossary-lookup' finds both formats.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

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

(defun blueprint--glossary-sections ()
  "Return the level-1 headings of the real glossary sections, in file order.
The :noexport: guide of the template and its example sub-sections are
left out: they are documentation, not sections to fill.  Creates the
glossary file first if it is absent.  Note: level-1 entries appended
by older Blueprint versions look like sections too; they appear in
the list but no harm is done -- a term added there simply lives in
its own level-1 section, exactly as it did before."
  (let ((file (blueprint--ensure-glossary))
        (sections '()))
    (with-temp-buffer
      (blueprint--insert-org-file file)
      (org-element-map (org-element-parse-buffer 'headline) 'headline
        (lambda (hl)
          (when (and (= (org-element-property :level hl) 1)
                     (not (org-element-property :commentedp hl))
                     (not (member "noexport"
                                  (org-element-property :tags hl))))
            (push (org-element-property :raw-value hl) sections)))))
    (nreverse sections)))

;;;###autoload
(defun blueprint-glossary-add (term definition source &optional section)
  "Add TERM with DEFINITION and SOURCE to the project glossary.
The entry is inserted as a level-2 heading at the end of SECTION, a
level-1 heading of glossary.org that defaults to the first one (by
convention \"Termini di dominio\"), in the format of the glossary
template: the definition followed by a /Fonte: .../ line.  Entries
written by older versions (level-1 headings with a :PROPERTIES:
drawer at the end of the file) are left untouched and remain
readable by `blueprint-glossary-lookup'."
  (interactive
   (let* ((sections (blueprint--glossary-sections))
          (term (read-string "Term: "))
          (definition (read-string "Definition: "))
          (source (read-string "Source: "))
          (section (completing-read "Section: " (or sections '("Termini di dominio"))
                                    nil t nil nil (car sections))))
     (list term definition source section)))
  (blueprint--ensure-glossary)
  (let* ((sections (blueprint--glossary-sections))
         (section (or section (car sections)))
         (file (blueprint--glossary-file)))
    (unless (member section sections)
      (user-error "Glossary section %S not found in glossary.org" section))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let* ((next-heading
                (catch 'found
                  (org-element-map (org-element-parse-buffer 'headline) 'headline
                    (lambda (hl)
                      (when (and (= (org-element-property :level hl) 1)
                                 (string= (org-element-property :raw-value hl)
                                          section)
                                 (not (member "noexport"
                                              (org-element-property :tags hl))))
                        ;; Contents of the section: insert before the
                        ;; next level-1 heading, or at the end of the
                        ;; file when this is the last one.
                        ;; An empty section has no contents: start
                        ;; from its end, which is the next heading.
                        (goto-char (or (org-element-property :contents-begin hl)
                                       (org-element-property :end hl)))
                        (throw 'found
                               (save-excursion
                                 (when (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)))))))))
               (insert-pos (or next-heading (point-max))))
          (unless next-heading
            (goto-char (point-max))
            (unless (bolp) (insert "\n")))
          (goto-char insert-pos)
          (unless (bolp) (insert "\n"))
          ;; Exactly one blank line before the new entry.
          (unless (save-excursion (forward-line -1) (looking-at "^\\s-*$"))
            (insert "\n"))
          (insert (format "** %s\n%s\n/Fonte: %s/\n" term definition source))
          ;; And one before the heading that follows, if any.
          (when (and next-heading (eq (char-after) ?*))
            (insert "\n"))))
      (save-buffer))
    (message "Added glossary term: %s (%s)" term section)))

;;;###autoload
(defun blueprint-glossary-list ()
  "Open the project glossary file."
  (interactive)
  (find-file (blueprint--ensure-glossary)))

;;;###autoload
(defun blueprint-glossary-lookup (term)
  "Search for TERM in the glossary and display its definition.
Both entry formats are found: the current one (level-2 headings
inside the glossary sections) and the legacy one (level-1 headings
with a :PROPERTIES: drawer at the end of the file).  Entries inside
the :noexport: guide of the template are not matched.  For a legacy
entry the drawer lines are not shown."
  (interactive "sLookup term: ")
  (let ((file (blueprint--glossary-file)))
    (unless (file-exists-p file)
      (user-error "No glossary file found"))
    (with-temp-buffer
      (blueprint--insert-org-file file)
      (let ((excluded (blueprint--non-exported-subtrees))
            (found nil))
        (goto-char (point-min))
        (while (and (not found)
                    (re-search-forward
                     (format "^\\*+ %s[ \t]*$" (regexp-quote term)) nil t))
          (when (not (blueprint--in-regions-p (point) excluded))
            (setq found t)))
        (if (not found)
            (message "Term \"%s\" not found in glossary" term)
          (let* ((level (save-excursion
                          (beginning-of-line)
                          (skip-chars-forward "*")
                          (- (point) (line-beginning-position))))
                 (start (line-beginning-position))
                 (end (or (save-excursion
                            (when (re-search-forward
                                   (format "^\\*\\{1,%d\\} " level) nil t)
                              (line-beginning-position)))
                          (point-max)))
                 (text (buffer-substring-no-properties start end)))
            (setq text (mapconcat
                        #'identity
                        (cl-remove-if
                         (lambda (line)
                           (string-match-p
                            "^:\\(PROPERTIES\\|SOURCE\\|END\\):" line))
                         (split-string text "\n"))
                        "\n"))
            (message "%s" (string-trim text))))))))

(provide 'blueprint-glossary)
;;; blueprint-glossary.el ends here
