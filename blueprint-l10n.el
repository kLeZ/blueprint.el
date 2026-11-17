;;; blueprint-l10n.el --- Document languages for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Everything about the language of the documents Blueprint writes
;; (docs/adr/ADR-003-localized-templates.org), in one place: the other
;; modules only call the functions below.
;;
;; This file holds code, not translations.  A language is a folder of
;; templates (templates/<lang>/ in the package,
;; ~/.config/blueprint/templates/<lang>/ for the user) with:
;; - the document templates, whose headings carry a
;;   :BLUEPRINT_SECTION: property: the title of a section in a
;;   language is the one its template gives it;
;; - snippets/, the skeletons the commands insert (feature, entity,
;;   flow...), filled in by `blueprint--snippet';
;; - strings.org, the short texts (file headers, risk values, the
;;   glossary source line), read by `blueprint--l10n'.
;; Adding a language adds files only.
;;
;; The only fixed text here describes an old format: the section
;; titles of the documents written by 0.4.x and earlier, which have no
;; property (`blueprint--legacy-section-titles').
;;
;; The user interface (prompts, messages, buffers) is English and is
;; not localized.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-element)

;; Defined in blueprint-core.el, which requires this file: called at
;; run time only.
(defvar blueprint-template-dir)
(defvar blueprint-user-template-dir)
(declare-function blueprint--root "blueprint-core" ())
(declare-function blueprint--data-path "blueprint-core" (relative &optional root))
(declare-function blueprint--version-file "blueprint-core" (&optional root))
(declare-function blueprint--org-keyword "blueprint-core" (file key))
(declare-function blueprint--file-stamp "blueprint-core" (file))
(declare-function blueprint--template "blueprint-core" (name))
(declare-function blueprint--resolve-template "blueprint-core" (name))

;;; --- Document language (docs/adr/ADR-003-localized-templates.org) ---

;; A language is a folder of templates: templates/<lang>/ in the
;; package, ~/.config/blueprint/templates/<lang>/ for the user.  It
;; holds the document templates, the skeletons the commands insert
;; (snippets/) and strings.org, the short texts of the language.  The
;; code holds no translated text: adding a language adds files only.

(defcustom blueprint-default-language "en"
  "Language of the document of a project created by `blueprint-init'.
A language code: the name of a folder of templates (see
`blueprint--languages').  The language is recorded in the project
\(#+BLUEPRINT_LANGUAGE: in the version file), so changing this option
never changes an existing project.  It picks the templates and the
text the commands insert."
  :type 'string
  :group 'blueprint)

(defconst blueprint--legacy-language "it"
  "Language of a project that declares none.
Every project created before languages existed is Italian.")

(defconst blueprint--fallback-language "en"
  "Language of a text or template missing in the requested language.")

(defvar blueprint--language nil
  "When non-nil, the document language, whatever the project declares.
`blueprint-init' binds it while it writes a new project.")

(defun blueprint--languages ()
  "Return the languages available, sorted.
The names of the language folders of `blueprint-template-dir' and of
`blueprint-user-template-dir': a two-letter code, optionally followed
by a region (\"pt-BR\")."
  (let ((langs '()))
    (dolist (dir (list blueprint-template-dir blueprint-user-template-dir))
      (when (file-directory-p dir)
        (dolist (name (directory-files dir nil "\\`[a-z][a-z]\\(?:[-_][A-Za-z]+\\)?\\'"))
          (when (file-directory-p (expand-file-name name dir))
            (push name langs)))))
    (sort (delete-dups langs) #'string<)))

;;; --- Template folders of a language ---

(defun blueprint--system-template-dir (&optional lang)
  "Return the directory of the system templates in LANG.
LANG defaults to the document language of the current project.  The
folder LANG of `blueprint-template-dir'; the folder of
`blueprint--fallback-language' when the package has none for LANG;
`blueprint-template-dir' itself when it has no language folders at
all (a flat directory configured by the user)."
  (let* ((lang (or lang (blueprint--project-language)))
         (dir (expand-file-name lang blueprint-template-dir))
         (fallback (expand-file-name blueprint--fallback-language
                                     blueprint-template-dir)))
    (file-name-as-directory
     (cond ((file-directory-p dir) dir)
           ((file-directory-p fallback) fallback)
           (t blueprint-template-dir)))))

(defun blueprint--user-template-dirs (&optional lang)
  "Return the user template directories for LANG, in lookup order.
The folder LANG of `blueprint-user-template-dir', then, for Italian,
the directory itself: before languages existed the user templates
were copied there, flat, and they are Italian."
  (let ((lang (or lang (blueprint--project-language))))
    (append (list (file-name-as-directory
                   (expand-file-name lang blueprint-user-template-dir)))
            (when (string= lang blueprint--legacy-language)
              (list (file-name-as-directory blueprint-user-template-dir))))))

(defconst blueprint--template-subdirs '("snippets")
  "Subfolders of a language folder of templates.")

(defun blueprint--template-files (dir &optional flat)
  "Return the template files of the language folder DIR.
Its Org files and those of `blueprint--template-subdirs'; with FLAT
non-nil only the Org files of DIR itself."
  (when (file-directory-p dir)
    (append (directory-files dir t "\\`[^.].*\\.org\\'")
            (unless flat
              (cl-mapcan (lambda (sub)
                           (let ((d (expand-file-name sub dir)))
                             (and (file-directory-p d)
                                  (directory-files d t "\\`[^.].*\\.org\\'"))))
                         blueprint--template-subdirs)))))

(defun blueprint--template-relative-name (file)
  "Return the name of the template FILE inside its language folder.
\"component.org\", or \"snippets/feature.org\" for a skeleton."
  (let ((parent (file-name-nondirectory
                 (directory-file-name (file-name-directory file)))))
    (if (member parent blueprint--template-subdirs)
        (concat parent "/" (file-name-nondirectory file))
      (file-name-nondirectory file))))

(defun blueprint--template-language (file &optional root)
  "Return the language of the template copy FILE.
The name of its language folder when it is one (`blueprint--languages'):
a user template under ~/.config/blueprint/templates/<lang>/.
Otherwise the language of the project at ROOT for a project template,
Italian for a template in the user directory itself (where earlier
versions copied the Italian templates)."
  (let* ((path (expand-file-name file))
         (folder (substring path 0 (- (length path)
                                      (length (blueprint--template-relative-name file)))))
         (name (file-name-nondirectory (directory-file-name folder))))
    (cond ((member name (blueprint--languages)) name)
          ((ignore-errors
             (file-equal-p folder (blueprint--data-path "templates" root)))
           (blueprint--project-language root))
          (t blueprint--legacy-language))))

;;; --- Language of the project ---

(defun blueprint--project-language (&optional root)
  "Return the document language of the project at ROOT.
The #+BLUEPRINT_LANGUAGE: of the version file; Italian
\(`blueprint--legacy-language') for a project that declares none;
`blueprint-default-language' outside any project.
`blueprint--language' overrides all of them."
  (or blueprint--language
      (let ((root (or root (ignore-errors (blueprint--root)))))
        (if (not root)
            blueprint-default-language
          (or (blueprint--org-keyword (blueprint--version-file root)
                                      "BLUEPRINT_LANGUAGE")
              blueprint--legacy-language)))))

;;; --- Short texts: strings.org of the language ---

(defvar blueprint--strings-cache (make-hash-table :test 'equal)
  "Parsed strings.org files: FILE -> (STAMP . ENTRIES).")

(defun blueprint--strings-parse (file)
  "Return the entries of the strings FILE, uncached.
An alist (KEY TEXT . ITEMS), one per level-1 heading: KEY is the
heading, TEXT the text under it (comments left out, trimmed), ITEMS
the texts of its list items."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (let ((entries '()))
      (org-element-map (org-element-parse-buffer) 'headline
        (lambda (hl)
          (when (= (org-element-property :level hl) 1)
            (let* ((section (car (org-element-contents hl)))
                   (parts '())
                   (items '()))
              (when (eq (org-element-type section) 'section)
                (dolist (el (org-element-contents section))
                  (pcase (org-element-type el)
                    ('comment nil)
                    ('plain-list
                     (org-element-map el 'item
                       (lambda (it)
                         (push (string-trim
                                (buffer-substring-no-properties
                                 (org-element-property :contents-begin it)
                                 (org-element-property :contents-end it)))
                               items))))
                    (_ (push (buffer-substring-no-properties
                              (org-element-property :begin el)
                              (org-element-property :end el))
                             parts)))))
              (push (cons (org-element-property :raw-value hl)
                          (cons (string-trim (apply #'concat (nreverse parts)))
                                (nreverse items)))
                    entries)))))
      (nreverse entries))))

(defun blueprint--strings-entries (file)
  "Return the entries of the strings FILE, cached until it changes."
  (let ((stamp (blueprint--file-stamp file))
        (hit (gethash file blueprint--strings-cache)))
    (if (and hit (equal (car hit) stamp))
        (cdr hit)
      (let ((entries (blueprint--strings-parse file)))
        (puthash file (cons stamp entries) blueprint--strings-cache)
        entries))))

(defun blueprint--strings-files (lang &optional root)
  "Return the strings.org files for LANG, in lookup order.
The project template directory (when LANG is the language of the
project at ROOT), the user directories of LANG, the system folder of
LANG, then the one of `blueprint--fallback-language'.  A key missing
in one file is looked up in the next one."
  (let ((project-dir (and (equal lang (blueprint--project-language root))
                          (ignore-errors (blueprint--data-path "templates" root)))))
    (cl-remove-if-not
     #'file-exists-p
     (delete-dups
      (mapcar (lambda (d) (expand-file-name "strings.org" d))
              (append (and project-dir (list project-dir))
                      (blueprint--user-template-dirs lang)
                      (list (blueprint--system-template-dir lang)
                            (blueprint--system-template-dir
                             blueprint--fallback-language))))))))

(defun blueprint--l10n-entry (key &optional root lang)
  "Return the entry (TEXT . ITEMS) of KEY in LANG, or signal an error.
LANG defaults to the document language of the project at ROOT."
  (let* ((lang (or lang (blueprint--project-language root)))
         (name (if (symbolp key) (symbol-name key) key)))
    (or (cl-some (lambda (file)
                   (cdr (assoc name (blueprint--strings-entries file))))
                 (blueprint--strings-files lang root))
        (error "Blueprint: no text %s in the strings.org of %s" name lang))))

(defun blueprint--l10n (key &optional root lang)
  "Return the text KEY of strings.org in the document language.
LANG defaults to the language of the project at ROOT (see
`blueprint--strings-files' for where the text is looked up)."
  (car (blueprint--l10n-entry key root lang)))

(defun blueprint--l10n-list (key &optional root lang)
  "Return the list items of KEY in strings.org.
LANG and ROOT as in `blueprint--l10n'."
  (cdr (blueprint--l10n-entry key root lang)))

;;; --- Snippets: the skeletons the commands insert ---

(defun blueprint--snippet (name replacements)
  "Return the skeleton NAME of the document language, filled in.
NAME is a file of the snippets/ folder of the templates (without
.org), resolved in the three tiers like the other templates.
REPLACEMENTS is an alist (PLACEHOLDER . VALUE): \"NAME\" replaces
{{NAME}}.  Leading comment lines are dropped; the text ends with one
blank line."
  (let ((text (blueprint--template (concat "snippets/" name ".org"))))
    (while (string-match "\\`#\\(?: .*\\)?\n" text)
      (setq text (substring text (match-end 0))))
    (dolist (pair replacements)
      (setq text (replace-regexp-in-string
                  (regexp-quote (format "{{%s}}" (car pair)))
                  (cdr pair) text t t)))
    (concat (string-trim-right text) "\n\n")))

(defun blueprint--insert-aligned (text)
  "Insert TEXT, a filled-in skeleton (`blueprint--snippet'), at point.
The tables of the inserted text are aligned: a value put into a cell
changes its width."
  (let ((start (point)))
    (insert text)
    (let ((end (copy-marker (point) t)))
      (when (derived-mode-p 'org-mode)
        (save-excursion
          (goto-char start)
          (while (re-search-forward "^[ \t]*|" end t)
            ;; Only real tables: the swimlanes of a PlantUML activity
            ;; diagram also start with "|", inside a src block.
            (if (org-at-table-p)
                (progn (org-table-align) (goto-char (org-table-end)))
              (forward-line 1)))))
      (goto-char end)
      (set-marker end nil))))

;;; --- Sections found by property or title ---

(defconst blueprint--legacy-section-titles
  '((introduction 1 "Introduction")
    (context-scope 1 "Context and Scope")
    (constraints 1 "Constraints")
    (solution-strategy 1 "Solution Strategy")
    (building-blocks 1 "Building Blocks")
    (runtime 1 "Runtime Behavior")
    (business-processes 1 "Processi di business")
    (deployment 1 "Deployment")
    (responsibility 1 "Responsibility")
    (risks 1 "Risks")
    (open-questions 1 "Open Questions")
    (diagrams 1 "Diagrams")
    (enterprise-context 1 "Contesto enterprise")
    (stakeholders 1 "Stakeholder e punti di contatto")
    (compliance 1 "Conformità e compliance")
    (functional-overview 1 "Panoramica del componente")
    (functional-areas 1 "Aree funzionali")
    (domain-entities 1 "Entità di dominio")
    (er-diagram 2 "Diagramma ER generale")
    (integration-points 1 "Punti di integrazione")
    (data-flows 1 "Flussi dati")
    (inventory 1 "Inventario")
    (deployment-view 1 "Deployment view")
    (infra-dependencies 1 "Dipendenze infrastrutturali")
    (configuration 1 "Configurazione rilevante")
    (environments 1 "Ambienti")
    (glossary-domain 1 "Termini di dominio")
    (glossary-technical 1 "Termini tecnici con uso specifico")
    (glossary-acronyms 1 "Acronimi e abbreviazioni")
    (references-documents 1 "Documenti")
    (references-interviews 1 "Interviste")
    (references-systems 1 "Sistemi e strumenti")
    (references-environments 1 "Ambienti analizzati")
    (quality-scenarios 1 "Scenari di qualità")
    (service-level 1 "Service Level")
    (risk-register 1 "Registro dei rischi")
    (constraints-cross 1 "Vincoli trasversali")
    (constraints-technical 2 "Vincoli tecnici")
    (constraints-organizational 2 "Vincoli organizzativi")
    (constraints-regulatory 2 "Vincoli normativi e di compliance"))
  "Sections as Blueprint 0.4.x and earlier wrote them: (ID LEVEL TITLE...).
Those documents have no :BLUEPRINT_SECTION: property, so their
sections are found by these titles.  A frozen description of an old
format (ADR-003, option C), like the Italian marker regexps: every
document written since has the property, so the list never grows.")

(defvar blueprint--section-map-cache (make-hash-table :test 'equal)
  "Section maps of the templates: (LANG FILES-AND-STAMPS) -> MAP.")

(defvar blueprint--section-files-cache (make-hash-table :test 'equal)
  "Template files of the sections: (LANG ROOT DIR-STAMPS) -> FILES.")

(defun blueprint--section-template-files (lang)
  "Return the template files that define the sections of LANG.
Every template of the system folder of LANG; for the language of the
current project, each one as the three tiers resolve it, so a
customized template defines the titles of its project."
  (let* ((sys (blueprint--system-template-dir lang))
         (own (equal lang (blueprint--project-language)))
         (root (and own (ignore-errors (blueprint--root))))
         ;; Resolving every template is the slow part; the result
         ;; changes only when a file is added to or removed from one
         ;; of the template directories, which changes its stamp.
         (dirs (append (and root (list (blueprint--data-path "templates" root)))
                       (and own (blueprint--user-template-dirs lang))
                       (list sys)))
         (key (list lang root (mapcar (lambda (d) (cons d (blueprint--file-stamp d)))
                                      dirs))))
    (or (gethash key blueprint--section-files-cache)
        (puthash key
                 (mapcar (lambda (name)
                           (or (and own (ignore-errors (blueprint--resolve-template name)))
                               (expand-file-name name sys)))
                         (directory-files sys nil "\\`[^.].*\\.org\\'"))
                 blueprint--section-files-cache))))

(defun blueprint--section-map (&optional lang)
  "Return the sections of the templates of LANG: an alist (ID TITLE . LEVEL).
LANG defaults to the document language of the current project.  The
title and level are those of the first heading that carries the
:BLUEPRINT_SECTION: property ID, outside the :noexport: guides."
  (let* ((lang (or lang (blueprint--project-language)))
         (files (blueprint--section-template-files lang))
         (key (cons lang (mapcar (lambda (f) (cons f (blueprint--file-stamp f)))
                                 files)))
         (hit (gethash key blueprint--section-map-cache)))
    (or hit
        (let ((map '()))
          (dolist (file files)
            (with-temp-buffer
              (insert-file-contents file)
              (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
              (org-element-map (org-element-parse-buffer 'headline) 'headline
                (lambda (hl)
                  (let ((id (org-element-property :BLUEPRINT_SECTION hl)))
                    (when (and id (not (blueprint--headline-excluded-p hl))
                               (not (assq (intern id) map)))
                      (push (cons (intern id)
                                  (cons (org-element-property :raw-value hl)
                                        (org-element-property :level hl)))
                            map)))))))
          (puthash key (nreverse map) blueprint--section-map-cache)))))

(defun blueprint--section-title (id &optional lang)
  "Return the title of section ID in LANG (default: the project language).
From the templates of the language (`blueprint--section-map'), else
the 0.4.x title, else the id itself."
  (or (cadr (assq id (blueprint--section-map lang)))
      (nth 2 (assq id blueprint--legacy-section-titles))
      (symbol-name id)))

(defun blueprint--section-level (id)
  "Return the heading level of section ID (default 1)."
  (or (cddr (assq id (blueprint--section-map)))
      (nth 1 (assq id blueprint--legacy-section-titles))
      1))

(defun blueprint--section-titles (id)
  "Return the titles that identify section ID in a heading without property.
Its title in the templates of the project language and its 0.4.x
titles (`blueprint--legacy-section-titles')."
  (delete-dups
   (delq nil (cons (cadr (assq id (blueprint--section-map)))
                   (nthcdr 2 (assq id blueprint--legacy-section-titles))))))

(defun blueprint--section-id-for-title (title level)
  "Return the id of the section whose title is TITLE at heading LEVEL.
The titles of `blueprint--section-titles', ignoring case; nil when no
section has that title."
  (let ((title (downcase title)))
    (or (car (cl-find-if (lambda (entry)
                           (and (= level (cddr entry))
                                (string= title (downcase (cadr entry)))))
                         (blueprint--section-map)))
        (car (cl-find-if (lambda (entry)
                           (and (= level (nth 1 entry))
                                (member title (mapcar #'downcase (nthcdr 2 entry)))))
                         blueprint--legacy-section-titles)))))

(defun blueprint--headline-excluded-p (hl)
  "Return non-nil if headline HL is commented or under a :noexport: tag."
  (cl-some (lambda (node)
             (and (eq (org-element-type node) 'headline)
                  (or (org-element-property :commentedp node)
                      (member "noexport" (org-element-property :tags node)))))
           (org-element-lineage hl nil t)))

(defun blueprint--section-find (id &optional level prefix)
  "Return the headline element of section ID in the current buffer, or nil.
First the headline whose :BLUEPRINT_SECTION: property is ID (at
LEVEL, when given); then, for files written before the property, a
headline at LEVEL (default: the level of the section) whose title is
one of `blueprint--section-titles', ignoring case.  With PREFIX
non-nil a title that only starts with one of them matches too, after
the exact ones (the lint always accepted \"Introduction and goals\"
for \"Introduction\").  Commented headlines and those under a
:noexport: tag never match."
  (let* ((tree (org-element-parse-buffer 'headline))
         (name (symbol-name id))
         (title-level (or level (blueprint--section-level id)))
         (titles (mapcar #'downcase (blueprint--section-titles id))))
    (or (org-element-map tree 'headline
          (lambda (hl)
            (and (equal (org-element-property :BLUEPRINT_SECTION hl) name)
                 (or (null level) (= (org-element-property :level hl) level))
                 (not (blueprint--headline-excluded-p hl))
                 hl))
          nil t)
        (org-element-map tree 'headline
          (lambda (hl)
            (and (= (org-element-property :level hl) title-level)
                 (member (downcase (org-element-property :raw-value hl)) titles)
                 (not (blueprint--headline-excluded-p hl))
                 hl))
          nil t)
        (and prefix
             (org-element-map tree 'headline
               (lambda (hl)
                 (let ((raw (downcase (org-element-property :raw-value hl))))
                   (and (= (org-element-property :level hl) title-level)
                        (cl-some (lambda (title) (string-prefix-p title raw))
                                 titles)
                        (not (blueprint--headline-excluded-p hl))
                        hl)))
               nil t)))))

(defun blueprint--section-heading (id level &optional _root)
  "Return the text of a new heading for section ID at LEVEL.
The title is the one of the templates of the project language, and
the heading carries the :BLUEPRINT_SECTION: property."
  (format "%s %s\n:PROPERTIES:\n:BLUEPRINT_SECTION: %s\n:END:\n"
          (make-string level ?*) (blueprint--section-title id) id))

(defun blueprint--section-goto-end (id &optional level)
  "Move point to the end of section ID at LEVEL (default 1).
That is before the next heading of LEVEL or above, or at the end of
the buffer.  Returns non-nil when the section exists; otherwise point
does not move and the result is nil."
  (let* ((level (or level 1))
         (hl (blueprint--section-find id level)))
    (when hl
      (goto-char (org-element-property :begin hl))
      (forward-line 1)
      (goto-char (or (save-excursion
                       (when (re-search-forward
                              (format "^\\*\\{1,%d\\} " level) nil t)
                         (line-beginning-position)))
                     (point-max)))
      t)))

(defun blueprint--section-ensure-end (id &optional level)
  "Move point to the end of section ID at LEVEL, creating it if absent.
A missing section is appended at the end of the buffer, with the
heading of `blueprint--section-heading' and a blank line."
  (let ((level (or level 1)))
    (unless (blueprint--section-goto-end id level)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (blueprint--section-heading id level) "\n"))))

(defun blueprint--section-bounds (section &optional level)
  "Return (BEG . END) of the body of SECTION at LEVEL, or nil.
SECTION is a section id (see `blueprint--section-find'); the body
runs from the line after its heading to the next heading of any
level, or to the end of the buffer."
  (let ((hl (blueprint--section-find section level)))
    (when hl
      (save-excursion
        (goto-char (org-element-property :begin hl))
        (forward-line 1)
        (cons (point)
              (if (re-search-forward "^\\*" nil t)
                  (match-beginning 0)
                (point-max)))))))

(defun blueprint--section-append-row (section row &optional level)
  "Append ROW after the last org-table line of SECTION at LEVEL.
Works on the current buffer.  SECTION is a section id, found by
property or title (`blueprint--section-find'): only real headings
count, so the examples of the :noexport: compilation guide (which
show tables of their own) are never the target.  If the section is
absent, appends its heading, in the document language, and the row
at the end of the buffer."
  (let ((bounds (blueprint--section-bounds section level))
        (last-pipe-pos nil))
    (when bounds
      (goto-char (car bounds))
      (while (re-search-forward "^|" (cdr bounds) t)
        (setq last-pipe-pos (line-end-position))))
    (cond
     (last-pipe-pos
      (goto-char last-pipe-pos)
      (insert "\n" (string-remove-suffix "\n" row)))
     (bounds
      (goto-char (cdr bounds))
      (unless (bolp) (insert "\n"))
      (insert row))
     (t
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (blueprint--section-heading section (or level 1)) row)))))


(defun blueprint--l10n-rank (value key)
  "Return the position of VALUE in the list KEY of strings.org, or nil.
VALUE may be in any available language, ignoring case: a risk
register written in one language is read in another."
  (cl-some (lambda (lang)
             (cl-position (downcase value)
                          (mapcar #'downcase (blueprint--l10n-list key nil lang))
                          :test #'string=))
           (blueprint--languages)))

(provide 'blueprint-l10n)
;;; blueprint-l10n.el ends here
