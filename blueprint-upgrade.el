;;; blueprint-upgrade.el --- Project version and optional migrations for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Blueprint reads every project layout it ever wrote, so a project
;; never has to be migrated before work goes on (docs/adr/ADR-002).
;; This module offers the migration as an option:
;;
;; - the project records its Blueprint version and the migrations
;;   applied in blueprint-version.org, in the data directory (written
;;   by `blueprint-init' and by every migration, never required: a
;;   project without it gets a version inferred from its layout);
;; - `blueprint-upgrade-steps' is the registry of the format changes
;;   since the first version, each with a read-only detector and an
;;   idempotent apply function;
;; - `blueprint-project-upgrade' shows the plan (pending steps and the
;;   status of the project and user templates) and applies what the
;;   user confirms, after a backup of every file it rewrites
;;   (`blueprint-upgrade-backup') and a check of the git working tree
;;   (`blueprint-upgrade-git-check');
;; - `blueprint--upgrade-summary' feeds the dashboard and the CI.
;;
;; Every future format change adds its step here (see AGENTS.md).

;;; Code:

(require 'blueprint-core)
(require 'blueprint-adr)
(require 'blueprint-glossary)
(require 'blueprint-references)
(require 'blueprint-migrate)
(require 'blueprint-template-history)
(require 'cl-lib)
(require 'org-element)
(require 'tabulated-list)

(declare-function blueprint-agenda-refresh "blueprint-agenda" ())
(declare-function blueprint--agenda-file "blueprint-agenda" ())
(declare-function blueprint--agenda-entries "blueprint-agenda" (&optional root))

;;; --- Settings ---

(defcustom blueprint-upgrade-backup t
  "When non-nil, `blueprint-project-upgrade' backs up every file first.
Each file a migration rewrites, moves or deletes is copied to a new
directory migration-YYYYMMDD-HHMMSS under
`blueprint-upgrade-backup-directory', with a report of the steps."
  :type 'boolean
  :group 'blueprint)

(defcustom blueprint-upgrade-backup-directory "_archive"
  "Directory, relative to the project root, of the migration backups.
`blueprint-init' creates _archive/ for archived material."
  :type 'string
  :group 'blueprint)

(defcustom blueprint-upgrade-git-check 'warn
  "What `blueprint-project-upgrade' does with uncommitted git changes.
`warn' says so and goes on (the backup still covers the files),
`refuse' stops until the working tree is clean, nil does not check."
  :type '(choice (const :tag "Warn and go on" warn)
                 (const :tag "Refuse to migrate" refuse)
                 (const :tag "Do not check" nil))
  :group 'blueprint)

(defcustom blueprint-template-status-scopes '(project user)
  "Template directories whose copies are compared with the system ones.
`project' is the templates/ directory of the data directory, `user'
is `blueprint-user-template-dir'."
  :type '(set (const :tag "Project templates" project)
              (const :tag "User templates" user))
  :group 'blueprint)

;;; --- Helpers for the steps ---

(defun blueprint--upgrade-rel (file root)
  "Return FILE relative to ROOT."
  (file-relative-name file root))

(defun blueprint--upgrade-has-keyword-p (file key)
  "Return non-nil when FILE has a #+KEY: line outside blocks, empty or not."
  (with-temp-buffer
    (blueprint--insert-org-file file)
    (org-element-map (org-element-parse-buffer 'element) 'keyword
      (lambda (kw) (string= (org-element-property :key kw) key))
      nil t)))

(defun blueprint--upgrade-tracked-p (root file)
  "Return non-nil when git tracks FILE in the work tree of ROOT."
  (blueprint--migrate-git-tracked-p root file))

(defun blueprint--upgrade-delete (root file)
  "Delete FILE of project ROOT, with `git rm' when git tracks it."
  (if (blueprint--upgrade-tracked-p root file)
      (let ((default-directory root))
        (with-temp-buffer
          (unless (eq 0 (process-file "git" nil t nil "rm" "-q" "--"
                                      (file-relative-name file root)))
            (user-error "Command git rm failed: %s" (string-trim (buffer-string))))))
    (delete-file file)))

(defun blueprint--upgrade-legacy-entries (file property)
  "Return the legacy level-1 entries of FILE carrying PROPERTY.
The format older versions appended to glossary.org and references.org:
a level-1 heading, a PROPERTIES drawer and a body.  A list of plists
\(:title :properties :body :begin :end), in file order; :properties is
an alist of the drawer, :body the text after the drawer, trimmed.
Headings the export leaves out (the template guides) are skipped."
  (when (file-exists-p file)
    (with-temp-buffer
      (blueprint--insert-org-file file)
      (let* ((tree (org-element-parse-buffer))
             (exclude (blueprint--export-exclude-tags tree))
             (entries '()))
        (org-element-map tree 'headline
          (lambda (hl)
            (when (and (= (org-element-property :level hl) 1)
                       (not (blueprint--excluded-headline-p hl exclude))
                       (org-element-property (intern (concat ":" property)) hl))
              (let* ((drawer (org-element-map hl 'property-drawer #'identity nil t))
                     (props (and drawer
                                 (org-element-map drawer 'node-property
                                   (lambda (np)
                                     (cons (org-element-property :key np)
                                           (org-element-property :value np))))))
                     (body-start (if drawer
                                     (org-element-property :end drawer)
                                   (org-element-property :contents-begin hl)))
                     (body-end (org-element-property :end hl)))
                (push (list :title (org-element-property :raw-value hl)
                            :properties props
                            :body (if (and body-start (< body-start body-end))
                                      (string-trim
                                       (buffer-substring-no-properties
                                        body-start body-end))
                                    "")
                            :begin (org-element-property :begin hl)
                            :end body-end)
                      entries)))))
        (nreverse entries)))))

(defun blueprint--upgrade-delete-regions (file regions)
  "Delete the (BEG . END) REGIONS of FILE on disk."
  (with-temp-buffer
    (insert-file-contents file)
    (dolist (r (sort (copy-sequence regions) (lambda (a b) (> (car a) (car b)))))
      (delete-region (car r) (cdr r)))
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (delete-region (point) (point-max))
    (insert "\n")
    (write-region (point-min) (point-max) file nil 'silent))
  (blueprint--upgrade-refresh-buffer file)
  (blueprint--invalidate-cache file))

(defun blueprint--upgrade-refresh-buffer (file)
  "Revert the buffer visiting FILE, if any, after a change on disk."
  (let ((buf (get-file-buffer file)))
    (when buf
      (with-current-buffer buf
        (unless (buffer-modified-p) (revert-buffer t t t))))))

(defun blueprint--upgrade-template-headings (template id name)
  "Return the level-1 body headings of TEMPLATE for component ID/NAME.
A list of (TITLE . ANCHOR-LINE-OR-NIL), in template order, outside the
:noexport: guide."
  (let ((text (blueprint--template template)))
    (setq text (replace-regexp-in-string "{{ID}}" id text t t))
    (setq text (replace-regexp-in-string "{{NAME}}" name text t t))
    (with-temp-buffer
      (insert text)
      (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
      (let* ((tree (org-element-parse-buffer 'headline))
             (exclude (blueprint--export-exclude-tags tree))
             (result '()))
        (org-element-map tree 'headline
          (lambda (hl)
            (when (and (= (org-element-property :level hl) 1)
                       (not (blueprint--excluded-headline-p hl exclude)))
              (let ((anchor
                     (save-excursion
                       (goto-char (org-element-property :begin hl))
                       (forward-line 1)
                       (and (looking-at "[ \t]*<<[^>]+>>[ \t]*$")
                            (string-trim (match-string 0))))))
                (push (cons (org-element-property :raw-value hl) anchor)
                      result)))))
        (nreverse result)))))

;;; --- Steps ---

(defun blueprint--upgrade-step-component-dirs (_root)
  "Detector: component directories not named with their id."
  (let ((found '()))
    (maphash (lambda (id dir)
               (unless (string= id (blueprint--component-id id))
                 (push dir found)))
             (blueprint--components))
    (sort found #'string<)))

(defun blueprint--upgrade-apply-component-dirs (root)
  "Rename the component directories to their id, fix master.org includes.
A directory whose id is taken by another component is left as it is
and reported."
  (let ((master (blueprint--master-file root))
        (renamed '()) (skipped '()))
    (maphash
     (lambda (id dir)
       (let ((new-id (blueprint--component-id id)))
         (unless (string= id new-id)
           (let ((target (expand-file-name new-id (file-name-directory
                                                   (directory-file-name dir)))))
             (if (file-exists-p target)
                 (push id skipped)
               (blueprint--migrate-rename root dir target)
               (push (cons id new-id) renamed))))))
     (blueprint--components))
    (when (and renamed (file-exists-p master))
      (with-temp-buffer
        (insert-file-contents master)
        (dolist (pair renamed)
          (goto-char (point-min))
          (let ((old (concat "/components/" (car pair) "/"))
                (new (concat "/components/" (cdr pair) "/")))
            (while (search-forward old nil t)
              (replace-match new t t))))
        (write-region (point-min) (point-max) master nil 'silent))
      (blueprint--upgrade-refresh-buffer master))
    (blueprint--invalidate-cache)
    (append (mapcar (lambda (p) (format "%s -> %s" (car p) (cdr p))) renamed)
            (mapcar (lambda (id) (format "%s: id %s already taken, left as is"
                                         id (blueprint--component-id id)))
                    skipped))))

(defun blueprint--upgrade-pre-010-p (file)
  "Return non-nil when FILE has the pre-0.1.0 component layout.
That layout had one level-1 heading, \"Component\", with the sections
as level-2 headings."
  (with-temp-buffer
    (blueprint--insert-org-file file)
    (let ((top (org-element-map (org-element-parse-buffer 'headline) 'headline
                 (lambda (hl)
                   (and (= (org-element-property :level hl) 1)
                        (org-element-property :raw-value hl))))))
      (equal top '("Component")))))

(defun blueprint--upgrade-step-pre-010 (_root)
  "Detector: component files with the pre-0.1.0 layout."
  (let ((found '()))
    (maphash (lambda (id _dir)
               (let ((file (blueprint--component-file id)))
                 (when (and (file-exists-p file)
                            (blueprint--upgrade-pre-010-p file))
                   (push file found))))
             (blueprint--components))
    (sort found #'string<)))

(defun blueprint--upgrade-apply-pre-010 (root)
  "Turn pre-0.1.0 component files into the arc42 layout.
The \"* Component\" heading goes, its sections become level-1,
\"Questions\" becomes \"Open Questions\", and the arc42 headings of
component.org that are missing are appended, empty."
  (let ((done '()))
    (dolist (file (blueprint--upgrade-step-pre-010 root))
      (let* ((id (file-name-nondirectory
                  (directory-file-name (file-name-directory file))))
             (name (or (blueprint--org-keyword file "TITLE") id)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Component[ \t]*$" nil t)
            (delete-region (line-beginning-position)
                           (min (point-max) (1+ (line-end-position)))))
          (goto-char (point-min))
          (while (re-search-forward "^\\*\\(\\*+\\) " nil t)
            (replace-match "\\1 " t nil))
          (goto-char (point-min))
          (while (re-search-forward "^\\* Questions[ \t]*$" nil t)
            (replace-match "* Open Questions" t t))
          (unless (save-excursion
                    (goto-char (point-min))
                    (re-search-forward "^#\\+TITLE:" nil t))
            (goto-char (point-min))
            (insert (format "#+TITLE: %s\n" name)))
          (let ((present (save-excursion
                           (goto-char (point-min))
                           (let (h)
                             (while (re-search-forward "^\\* \\(.*?\\)[ \t]*$" nil t)
                               (push (match-string 1) h))
                             h))))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (dolist (h (blueprint--upgrade-template-headings
                        "component.org" (blueprint--component-id id) name))
              (unless (member (car h) present)
                (insert "\n* " (car h) "\n")
                (when (cdr h) (insert (cdr h) "\n")))))
          (write-region (point-min) (point-max) file nil 'silent))
        (blueprint--upgrade-refresh-buffer file)
        (blueprint--invalidate-cache file)
        (push (blueprint--upgrade-rel file root) done)))
    (nreverse done)))

(defun blueprint--upgrade-step-adr-files (_root)
  "Detector: ADRs written one file per ADR."
  (blueprint--adr-legacy-files))

(defun blueprint--upgrade-apply-adr-files (root)
  "Move the one-file ADRs into adr.org and delete their files.
Each becomes a `* ADR NNNN: Title' heading with STATUS and DATE in the
drawer and the body of the file, headings one level down.  An ADR
whose number is already a heading of adr.org is left in its file and
reported."
  (let ((adr (blueprint--adr-ensure-file))
        (moved '()) (skipped '()))
    (dolist (file (blueprint--adr-legacy-files))
      (let* ((e (blueprint--adr-legacy-entry file))
             (num (plist-get e :number))
             (exists (with-temp-buffer
                       (insert-file-contents adr)
                       (goto-char (point-min))
                       (re-search-forward
                        (format "^\\* ADR %s:" (regexp-quote num)) nil t))))
        (if exists
            (push (format "%s: ADR %s already in adr.org, file kept"
                          (file-name-nondirectory file) num)
                  skipped)
          (let ((body (with-temp-buffer
                        (insert-file-contents file)
                        (goto-char (point-min))
                        (while (re-search-forward
                                "^#\\+\\(TITLE\\|DATE\\|STATUS\\):.*\n?" nil t)
                          (replace-match "" t t))
                        (goto-char (point-min))
                        (while (re-search-forward "^\\(\\*+\\) " nil t)
                          (replace-match "*\\1 " t nil))
                        (string-trim (buffer-string)))))
            (with-temp-buffer
              (insert-file-contents adr)
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert "\n"
                      (format "* ADR %s: %s\n" num (plist-get e :title))
                      ":PROPERTIES:\n"
                      (format ":STATUS: %s\n" (plist-get e :status))
                      (if (plist-get e :date)
                          (format ":DATE:   %s\n" (plist-get e :date))
                        "")
                      ":END:\n"
                      (if (string-empty-p body) "" (concat "\n" body "\n")))
              (write-region (point-min) (point-max) adr nil 'silent))
            (blueprint--upgrade-delete root file)
            (push (format "ADR %s: %s" num (plist-get e :title)) moved)))))
    (blueprint--upgrade-refresh-buffer adr)
    (blueprint--invalidate-cache)
    (append (nreverse moved) (nreverse skipped))))

(defun blueprint--upgrade-step-orphan-glossary (_root)
  "Detector: glossary file written inside the data directory."
  (let ((f (blueprint--glossary-orphan-file))) (and f (list f))))

(defun blueprint--upgrade-apply-orphan-glossary (root)
  "Move the terms of the orphan glossary into glossary.org, delete it.
Each term becomes an entry of the first section; a term the glossary
already has is reported and not added twice."
  (let ((orphan (blueprint--glossary-orphan-file))
        (done '()))
    (when orphan
      (blueprint--ensure-glossary)
      (with-temp-buffer
        (blueprint--insert-org-file orphan)
        (let* ((tree (org-element-parse-buffer))
               (exclude (blueprint--export-exclude-tags tree)))
          (org-element-map tree 'headline
            (lambda (hl)
              (when (and (= (org-element-property :level hl) 1)
                         (not (blueprint--excluded-headline-p hl exclude)))
                (let* ((term (org-element-property :raw-value hl))
                       (source (or (org-element-property :SOURCE hl) ""))
                       (drawer (org-element-map hl 'property-drawer #'identity nil t))
                       (start (if drawer (org-element-property :end drawer)
                                (org-element-property :contents-begin hl)))
                       (end (org-element-property :end hl))
                       (definition (if (and start (< start end))
                                       (string-trim (buffer-substring-no-properties start end))
                                     "")))
                  (push (list term definition source) done)))))))
      (setq done (nreverse done))
      (let ((report '()))
        (dolist (entry done)
          (if (blueprint--glossary-find-term (blueprint--glossary-file) (car entry))
              (push (format "%s: already in glossary.org, not duplicated" (car entry)) report)
            (blueprint-glossary-add (nth 0 entry) (nth 1 entry) (nth 2 entry))
            (push (car entry) report)))
        (blueprint--upgrade-delete root orphan)
        (nreverse report)))))

(defun blueprint--upgrade-orphan-references-file ()
  "Return the references file written inside the data directory, or nil."
  (let ((file (blueprint--data-path "references.org")))
    (and (file-exists-p file)
         (not (file-equal-p file (blueprint--references-file)))
         file)))

(defun blueprint--upgrade-step-orphan-references (_root)
  "Detector: references file written inside the data directory."
  (let ((f (blueprint--upgrade-orphan-references-file))) (and f (list f))))

(defun blueprint--upgrade-reference-rows (entries)
  "Add the legacy reference ENTRIES as table rows of references.org.
ENTRIES come from `blueprint--upgrade-legacy-entries' on :TYPE:.
Returns the titles added."
  (mapcar (lambda (e)
            (let* ((props (plist-get e :properties))
                   (type (or (cdr (assoc "TYPE" props)) "document"))
                   (type (if (member type '("interview" "document" "codebase"
                                            "ticket" "monitoring"))
                             type "document")))
              (blueprint--references-add-row
               (plist-get e :title) type (plist-get e :body)
               (cdr (assoc "DATE" props)))
              (plist-get e :title)))
          entries))

(defun blueprint--upgrade-apply-orphan-references (root)
  "Move the references of the orphan file into references.org, delete it."
  (let ((orphan (blueprint--upgrade-orphan-references-file)))
    (when orphan
      (prog1 (blueprint--upgrade-reference-rows
              (blueprint--upgrade-legacy-entries orphan "TYPE"))
        (blueprint--upgrade-delete root orphan)))))

(defun blueprint--upgrade-step-references-entries (_root)
  "Detector: references.org with level-1 entries of the old format."
  (let ((file (blueprint--references-file)))
    (and (blueprint--upgrade-legacy-entries file "TYPE") (list file))))

(defun blueprint--upgrade-apply-references-entries (_root)
  "Turn the old-format references of references.org into table rows."
  (let* ((file (blueprint--references-file))
         (entries (blueprint--upgrade-legacy-entries file "TYPE")))
    (when entries
      (blueprint--upgrade-delete-regions
       file (mapcar (lambda (e) (cons (plist-get e :begin) (plist-get e :end)))
                    entries))
      (prog1 (blueprint--upgrade-reference-rows entries)
        (blueprint--upgrade-refresh-buffer file)))))

(defun blueprint--upgrade-step-glossary-entries (_root)
  "Detector: glossary.org with level-1 entries of the old format."
  (let ((file (blueprint--glossary-file)))
    (and (blueprint--upgrade-legacy-entries file "SOURCE") (list file))))

(defun blueprint--upgrade-apply-glossary-entries (_root)
  "Turn the old-format terms of glossary.org into entries of a section.
Each goes to the end of the first section, in the format of
`blueprint-glossary-add'."
  (let* ((file (blueprint--glossary-file))
         (entries (blueprint--upgrade-legacy-entries file "SOURCE")))
    (when entries
      (blueprint--upgrade-delete-regions
       file (mapcar (lambda (e) (cons (plist-get e :begin) (plist-get e :end)))
                    entries))
      (mapcar (lambda (e)
                (blueprint-glossary-add
                 (plist-get e :title) (plist-get e :body)
                 (or (cdr (assoc "SOURCE" (plist-get e :properties))) ""))
                (plist-get e :title))
              entries))))

(defconst blueprint--upgrade-project-files
  '(("master.org" . "master.org")
    ("glossary.org" . "glossary.org")
    ("references.org" . "references.org")
    ("enterprise/context.org" . "enterprise-context.org")
    ("enterprise/dependencies.org" . "enterprise-dependencies.org")
    ("nfr/quality-scenarios.org" . "nfr-quality.org")
    ("nfr/constraints.org" . "nfr-constraints.org")
    ("nfr/risks.org" . "nfr-risks.org"))
  "Project files `blueprint-init' creates, with their template.")

(defun blueprint--upgrade-step-project-files (root)
  "Detector: project files `blueprint-init' creates that are missing."
  (delq nil (mapcar (lambda (pair)
                      (let ((f (expand-file-name (car pair) root)))
                        (unless (file-exists-p f) f)))
                    blueprint--upgrade-project-files)))

(defun blueprint--upgrade-apply-project-files (root)
  "Create the missing project files from their templates.
Existing files are never touched.  A master.org created here includes
the components after the next `blueprint-sync'."
  (let ((replacements
         `(("{{PROJECT}}" . ,(file-name-nondirectory (directory-file-name root)))
           ("{{AUTHOR}}" . ,(user-full-name))
           ("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))))
        (done '()))
    (make-directory (expand-file-name "_archive" root) t)
    (dolist (pair blueprint--upgrade-project-files)
      (let ((f (expand-file-name (car pair) root)))
        (unless (file-exists-p f)
          (blueprint--init-file f (cdr pair) replacements)
          (push (car pair) done))))
    (nreverse done)))

(defconst blueprint--upgrade-sync-pairs
  '(("arc42" blueprint-sync-start-marker blueprint-sync-end-marker)
    ("functional" blueprint-sync-functional-start-marker
     blueprint-sync-functional-end-marker)
    ("infrastructure" blueprint-sync-infra-start-marker
     blueprint-sync-infra-end-marker))
  "The sync sections of master.org: name, start and end marker variables.")

(defun blueprint--upgrade-missing-sync-pairs (master)
  "Return the entries of `blueprint--upgrade-sync-pairs' absent in MASTER."
  (with-temp-buffer
    (insert-file-contents master)
    (cl-remove-if (lambda (pair)
                    (goto-char (point-min))
                    (search-forward (symbol-value (nth 1 pair)) nil t))
                  blueprint--upgrade-sync-pairs)))

(defun blueprint--upgrade-step-master-sections (root)
  "Detector: master.org without some of the three sync sections."
  (let ((master (blueprint--master-file root)))
    (and (file-exists-p master)
         (blueprint--upgrade-missing-sync-pairs master)
         (list master))))

(defun blueprint--upgrade-template-sync-heading (start-marker)
  "Return the heading line that precedes START-MARKER in master.org's template.
The template resolved in the three tiers first; when that copy has no
such marker (an old project or user copy, the very case this step
migrates), the system template."
  (cl-some (lambda (file)
             (when (and file (file-exists-p file))
               (with-temp-buffer
                 (insert-file-contents file)
                 (goto-char (point-min))
                 (when (search-forward start-marker nil t)
                   (when (re-search-backward "^\\* .*$" nil t)
                     (match-string 0))))))
           (list (blueprint--resolve-template "master.org")
                 (expand-file-name "master.org" blueprint-template-dir))))

(defun blueprint--upgrade-apply-master-sections (root)
  "Append the missing sync sections to master.org.
Each comes with the heading the master.org template gives it and its
empty marker pair; the next `blueprint-sync' fills it.  The rest of
master.org is left as it is."
  (let ((master (blueprint--master-file root))
        (done '()))
    (when (file-exists-p master)
      (let ((missing (blueprint--upgrade-missing-sync-pairs master)))
        (when missing
          (with-temp-buffer
            (insert-file-contents master)
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (dolist (pair missing)
              (let* ((start (symbol-value (nth 1 pair)))
                     (end (symbol-value (nth 2 pair)))
                     (heading (or (blueprint--upgrade-template-sync-heading start)
                                  (format "* %s" (car pair)))))
                (insert "\n" heading "\n" start "\n" end "\n")
                (push (car pair) done)))
            (write-region (point-min) (point-max) master nil 'silent))
          (blueprint--upgrade-refresh-buffer master)
          (blueprint--invalidate-cache master))))
    (nreverse done)))

(defun blueprint--upgrade-step-component-documents (_root)
  "Detector: functional.org / infrastructure.org missing for a component."
  (let ((found '()))
    (maphash (lambda (_id dir)
               (dolist (f '("functional.org" "infrastructure.org"))
                 (let ((path (expand-file-name f dir)))
                   (when (and (not (file-exists-p path))
                              (blueprint--resolve-template f))
                     (push path found)))))
             (blueprint--components))
    (sort found #'string<)))

(defun blueprint--upgrade-apply-component-documents (root)
  "Create the missing functional.org and infrastructure.org from templates."
  (let ((done '()))
    (dolist (path (blueprint--upgrade-step-component-documents root))
      (let* ((dir (file-name-directory path))
             (id (file-name-nondirectory (directory-file-name dir)))
             (name (or (blueprint--org-keyword (expand-file-name "arc42.org" dir)
                                               "TITLE")
                       id)))
        (blueprint--init-file path (file-name-nondirectory path)
                              `(("{{NAME}}" . ,name)
                                ("{{ID}}" . ,(blueprint--component-id id))
                                ("{{DATE}}" . ,(format-time-string "%Y-%m-%d"))))
        (push (blueprint--upgrade-rel path root) done)))
    (nreverse done)))

(defun blueprint--upgrade-step-lifecycle (_root)
  "Detector: arc42.org files without a #+BLUEPRINT_LIFECYCLE: line."
  (let ((found '()))
    (maphash (lambda (id _dir)
               (let ((file (blueprint--component-file id)))
                 (when (and (file-exists-p file)
                            (not (blueprint--upgrade-has-keyword-p
                                  file "BLUEPRINT_LIFECYCLE")))
                   (push file found))))
             (blueprint--components))
    (sort found #'string<)))

(defun blueprint--upgrade-apply-lifecycle (root)
  "Declare #+BLUEPRINT_LIFECYCLE: active where the keyword is missing.
The line goes after the last keyword line of the file header (before
the first heading), as in the component template; the value is the
one the code already assumed for these components."
  (let ((done '()))
    (dolist (file (blueprint--upgrade-step-lifecycle root))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((pos (point-min)))
          (while (and (not (eobp))
                      (not (looking-at "^\\*")))
            (when (looking-at "^#\\+[A-Za-z_]+:")
              (setq pos (line-beginning-position 2)))
            (forward-line 1))
          (goto-char pos)
          (unless (bolp) (insert "\n"))
          (insert "#+BLUEPRINT_LIFECYCLE: active\n"))
        (write-region (point-min) (point-max) file nil 'silent))
      (blueprint--upgrade-refresh-buffer file)
      (blueprint--invalidate-cache file)
      (push (blueprint--upgrade-rel file root) done))
    (nreverse done)))

(defun blueprint--upgrade-step-agenda-ids (_root)
  "Detector: agenda.org with entries still keyed by the 0.3.0 IDs."
  (require 'blueprint-agenda)
  (let ((file (blueprint--agenda-file)))
    (when (file-exists-p file)
      (let ((content (with-temp-buffer (insert-file-contents file) (buffer-string))))
        (when (cl-some (lambda (e)
                         (and (not (string-match-p
                                    (concat ":ID: " (plist-get e :id) "$") content))
                              (string-match-p
                               (concat ":ID: " (plist-get e :legacy-id) "$") content)))
                       (blueprint--agenda-entries))
          (list file))))))

(defun blueprint--upgrade-apply-agenda-ids (_root)
  "Regenerate agenda.org: the refresh moves the old IDs to the new ones
and keeps DEADLINE, SCHEDULED, CLOSED and state."
  (require 'blueprint-agenda)
  (list (blueprint--upgrade-rel (blueprint-agenda-refresh) (blueprint--root))))

(defun blueprint--upgrade-step-version-file (root)
  "Detector: no blueprint-version.org (version not declared)."
  (let ((file (blueprint--version-file root)))
    (unless (file-exists-p file) (list file))))

(defun blueprint--upgrade-apply-version-file (_root)
  "Nothing to do here: `blueprint-upgrade-apply' writes the file."
  (list "blueprint-version.org"))

(defun blueprint--upgrade-step-data-directory (root)
  "Detector: project on the legacy .blueprint directory while
`blueprint-directory-name' names another one."
  (let ((configured (blueprint--directory-name)))
    (and (not (string= configured blueprint--legacy-directory-name))
         (not (file-directory-p (expand-file-name configured root)))
         (file-directory-p (expand-file-name blueprint--legacy-directory-name root))
         (list (expand-file-name blueprint--legacy-directory-name root)))))

(defun blueprint--upgrade-apply-data-directory (_root)
  "Rename the data directory with `blueprint-migrate-directory'."
  (blueprint-migrate-directory (blueprint--directory-name) t)
  (list (format "%s -> %s" blueprint--legacy-directory-name
                (blueprint--directory-name))))

(defvar blueprint-upgrade-steps
  `((:id "component-arc42-layout"
     :era "precedente a 0.1.0"
     :title "Componenti con la struttura arc42 (al posto di \"* Component\")"
     :detect blueprint--upgrade-step-pre-010
     :apply blueprint--upgrade-apply-pre-010)
    (:id "component-dir-ids"
     :era "0.1.0 o 0.2.0 (fino a 2026-02)"
     :title "Directory dei componenti rinominate con l'id (slug)"
     :detect blueprint--upgrade-step-component-dirs
     :apply blueprint--upgrade-apply-component-dirs)
    (:id "project-files"
     :era "0.1.0 o 0.2.0 (fino a 2026-02)"
     :title "File di progetto mancanti creati dai template (vuoti: il lint li segnala finche' non si compilano)"
     :detect blueprint--upgrade-step-project-files
     :apply blueprint--upgrade-apply-project-files)
    (:id "master-sync-sections"
     :era "0.1.0 o 0.2.0 (fino a 2026-02)"
     :title "Sezioni sincronizzate mancanti in master.org"
     :detect blueprint--upgrade-step-master-sections
     :apply blueprint--upgrade-apply-master-sections)
    (:id "component-documents"
     :era "0.1.0 o 0.2.0 (fino a 2026-02)"
     :title "functional.org e infrastructure.org mancanti creati nei componenti (vuoti: il lint li segnala)"
     :detect blueprint--upgrade-step-component-documents
     :apply blueprint--upgrade-apply-component-documents)
    (:id "adr-single-file"
     :era "0.2.0 (fino a 2026-03)"
     :title "ADR da un file ciascuno ad adr.org"
     :detect blueprint--upgrade-step-adr-files
     :apply blueprint--upgrade-apply-adr-files)
    (:id "orphan-glossary"
     :era "0.2.0 (fino a 2026-09)"
     :title "Termini del glossario scritto nella data directory"
     :detect blueprint--upgrade-step-orphan-glossary
     :apply blueprint--upgrade-apply-orphan-glossary)
    (:id "orphan-references"
     :era "0.2.0 (fino a 2026-09)"
     :title "Riferimenti scritti nella data directory"
     :detect blueprint--upgrade-step-orphan-references
     :apply blueprint--upgrade-apply-orphan-references)
    (:id "references-table-rows"
     :era "0.2.0 (fino a 2026-09)"
     :title "Riferimenti nel formato precedente convertiti in righe di tabella"
     :detect blueprint--upgrade-step-references-entries
     :apply blueprint--upgrade-apply-references-entries)
    (:id "data-directory"
     :era "0.2.0 (fino a 2026-09)"
     :title "Directory dati .blueprint rinominata in blueprint-directory-name"
     :detect blueprint--upgrade-step-data-directory
     :apply blueprint--upgrade-apply-data-directory)
    (:id "glossary-sections"
     :era "0.2.0 (fino a 2026-10)"
     :title "Termini del glossario nel formato precedente spostati nelle sezioni"
     :detect blueprint--upgrade-step-glossary-entries
     :apply blueprint--upgrade-apply-glossary-entries)
    (:id "lifecycle-keyword"
     :era "0.2.0 (fino a 2026-10)"
     :title "#+BLUEPRINT_LIFECYCLE: active dichiarato nei componenti"
     :detect blueprint--upgrade-step-lifecycle
     :apply blueprint--upgrade-apply-lifecycle)
    (:id "agenda-ids"
     :era "0.3.0"
     :title "ID dell'agenda rigenerati (date e stati conservati)"
     :detect blueprint--upgrade-step-agenda-ids
     :apply blueprint--upgrade-apply-agenda-ids)
    (:id "version-file"
     :era nil
     :title "Versione Blueprint dichiarata in blueprint-version.org"
     :detect blueprint--upgrade-step-version-file
     :apply blueprint--upgrade-apply-version-file))
  "Registry of the optional migration steps, oldest format first.
Each step is a plist: :id (recorded in blueprint-version.org), :era
\(the layout it migrates from, used to infer the version of an
unversioned project; nil for a step that says nothing about the
layout), :title, :detect (function of the root returning the files
the step touches, nil when nothing is pending; read-only) and :apply
\(function of the root, idempotent, returning lines for the report).
The steps are in chronological order of the formats they migrate
from.  Blueprint reads every one of these formats without the
migration.")

;;; --- Plan ---

(defun blueprint--upgrade-pending (&optional root)
  "Return the pending steps of the project at ROOT, in registry order.
A list of (STEP . FILES).  A detector that fails is reported as a
message and counts as not pending: the plan never breaks a command."
  (let* ((root (or root (blueprint--root)))
         (default-directory (file-name-as-directory root))
         (pending '()))
    (dolist (step blueprint-upgrade-steps)
      (let ((files (condition-case err
                       (funcall (plist-get step :detect) root)
                     (error
                      (message "Blueprint upgrade: detector %s failed: %s"
                               (plist-get step :id) (error-message-string err))
                      nil))))
        (when files (push (cons step files) pending))))
    (nreverse pending)))

(defun blueprint--project-version (&optional root pending)
  "Return (VERSION . SOURCE) of the project at ROOT.
SOURCE is `declared' when blueprint-version.org gives the version,
`inferred' otherwise: the era of the oldest PENDING step that has one
\(computed when not given; the registry is in chronological order),
or the package version when no such step is pending."
  (let* ((root (or root (blueprint--root)))
         (declared (car (blueprint--version-read root))))
    (if declared
        (cons declared 'declared)
      (let* ((pending (or pending (blueprint--upgrade-pending root)))
             (era (cl-some (lambda (p) (plist-get (car p) :era)) pending)))
        (cons (or era (blueprint-package-version)) 'inferred)))))

;;; --- Templates ---

(defun blueprint--file-md5 (file)
  "Return the MD5 of the bytes of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'md5 (current-buffer))))

(defun blueprint--template-status (file)
  "Return the status of the template copy FILE.
`current' when it is the system template, `stale' when it is an
unmodified older version of it (`blueprint--template-history'),
`customized' when it matches no version, `unknown' when the package
has no template of that name."
  (let* ((name (file-name-nondirectory file))
         (system (expand-file-name name blueprint-template-dir))
         (md5 (blueprint--file-md5 file)))
    (cond ((not (file-exists-p system)) 'unknown)
          ((string= md5 (blueprint--file-md5 system)) 'current)
          ((member md5 (cdr (assoc name blueprint--template-history))) 'stale)
          (t 'customized))))

(defun blueprint--template-scope-dir (scope &optional root)
  "Return the template directory of SCOPE (`project' or `user')."
  (pcase scope
    ('project (blueprint--data-path "templates" root))
    ('user blueprint-user-template-dir)))

(defun blueprint--template-statuses (&optional root)
  "Return the status of every template copy of the checked scopes.
A list of (SCOPE FILE STATUS), for the scopes of
`blueprint-template-status-scopes'; templates with status `current'
or `unknown' are left out."
  (let ((result '()))
    (dolist (scope blueprint-template-status-scopes)
      (let ((dir (blueprint--template-scope-dir scope root)))
        (when (and dir (file-directory-p dir))
          (dolist (f (directory-files dir t "\\`[^.].*\\.org\\'"))
            (let ((status (blueprint--template-status f)))
              (when (memq status '(stale customized))
                (push (list scope f status) result)))))))
    (nreverse result)))

(defun blueprint--template-update (file &optional backup-dir)
  "Replace the stale template copy FILE with the current system one.
The old copy goes first to BACKUP-DIR (default: a backup-TIMESTAMP
directory next to FILE).  Refuses a customized copy: its changes
would be lost.  Returns the backup path."
  (unless (eq (blueprint--template-status file) 'stale)
    (user-error "%s is not an unmodified older template: compare it with the diff"
                file))
  (let* ((dir (or backup-dir
                  (expand-file-name (format-time-string "backup-%Y%m%d-%H%M%S")
                                    (file-name-directory file))))
         (backup (expand-file-name (file-name-nondirectory file) dir)))
    (make-directory dir t)
    (copy-file file backup t)
    (delete-file file)
    (blueprint--copy-file-writable
     (expand-file-name (file-name-nondirectory file) blueprint-template-dir) file)
    backup))

(defun blueprint--template-diff (file)
  "Show the diff between the system template and its copy FILE."
  (diff (expand-file-name (file-name-nondirectory file) blueprint-template-dir)
        file nil 'noasync))

;;; --- Summary (dashboard, CI) ---

(defun blueprint--upgrade-summary (&optional root)
  "Return the upgrade state of the project at ROOT, as a plist.
:version and :source (see `blueprint--project-version'), :package
\(the installed version), :pending (step ids), :templates (number of
stale template copies) and :customized (number of customized ones).
Never signals: a failure gives nil."
  (condition-case nil
      (let* ((root (or root (blueprint--root)))
             (pending (blueprint--upgrade-pending root))
             (version (blueprint--project-version root pending))
             (templates (blueprint--template-statuses root)))
        (list :version (car version)
              :source (cdr version)
              :package (blueprint-package-version)
              :pending (mapcar (lambda (p) (plist-get (car p) :id)) pending)
              :templates (cl-count 'stale templates
                                   :key (lambda (e) (nth 2 e)))
              :customized (cl-count 'customized templates
                                    :key (lambda (e) (nth 2 e)))))
    (error nil)))

;;; --- Apply ---

(defun blueprint--upgrade-git-dirty-p (root)
  "Return non-nil when ROOT is a git work tree with uncommitted changes."
  (and (executable-find "git")
       (let ((default-directory root))
         (with-temp-buffer
           (and (eq 0 (process-file "git" nil t nil "status" "--porcelain"))
                (> (buffer-size) 0))))))

(defun blueprint--upgrade-git-check (root)
  "Apply `blueprint-upgrade-git-check' to ROOT before a migration."
  (when (and blueprint-upgrade-git-check
             (blueprint--upgrade-git-dirty-p root))
    (if (eq blueprint-upgrade-git-check 'refuse)
        (user-error "Uncommitted changes in the git working tree: commit or stash them first (blueprint-upgrade-git-check is `refuse')")
      (message "Blueprint upgrade: the git working tree has uncommitted changes; the backup covers the migrated files"))))

(defun blueprint--upgrade-backup-files (root files dir)
  "Copy the existing FILES of ROOT under DIR, keeping their relative path."
  (dolist (f files)
    (when (file-exists-p f)
      (let ((target (expand-file-name (file-relative-name f root) dir)))
        (make-directory (file-name-directory (directory-file-name target)) t)
        (if (file-directory-p f)
            (copy-directory f target t t)
          (copy-file f target t t))))))

(defun blueprint--upgrade-check-buffers (files)
  "Signal `user-error' when one of FILES has unsaved changes in a buffer.
A migration writes on disk: the buffer would keep the old text, and
saving it later would bring the old format back or lose the
migration.  Directories cover every file under them."
  (let ((dirty
         (cl-remove-if-not
          (lambda (buf)
            (let ((name (buffer-file-name buf)))
              (and name (buffer-modified-p buf)
                   (cl-some (lambda (f)
                              (let ((f (expand-file-name f))
                                    (n (expand-file-name name)))
                                (or (string= f n)
                                    (string-prefix-p (file-name-as-directory f) n))))
                            files))))
          (buffer-list))))
    (when dirty
      (user-error "Save or revert first: %s"
                  (mapconcat #'buffer-name dirty ", ")))))

(defun blueprint-upgrade-apply (&optional ids root)
  "Apply the pending migration steps IDS to the project at ROOT.
IDS nil applies every pending step.  Refuses while a file to migrate
has unsaved changes in a buffer, runs the git check, backs up the
files the steps touch (`blueprint-upgrade-backup'), applies the steps
in registry order and records them in blueprint-version.org; the
version becomes the package version when nothing is left pending.
Returns a plist (:applied :report :backup)."
  (let* ((root (file-name-as-directory (expand-file-name (or root (blueprint--root)))))
         (default-directory root)
         (pending (cl-remove-if-not
                   (lambda (p) (or (null ids)
                                   (member (plist-get (car p) :id) ids)))
                   (blueprint--upgrade-pending root)))
         (backup (and pending blueprint-upgrade-backup
                      (expand-file-name
                       (format-time-string "migration-%Y%m%d-%H%M%S")
                       (expand-file-name blueprint-upgrade-backup-directory root))))
         (report '())
         (applied '()))
    (when pending
      (blueprint--upgrade-check-buffers (apply #'append (mapcar #'cdr pending)))
      (blueprint--upgrade-git-check root)
      (when backup
        (make-directory backup t)
        (blueprint--upgrade-backup-files
         root (apply #'append (list (blueprint--version-file root))
                     (mapcar #'cdr pending))
         backup))
      (dolist (p pending)
        (let* ((step (car p))
               (lines (funcall (plist-get step :apply) root)))
          (push (plist-get step :id) applied)
          (push (cons step lines) report)))
      (setq applied (nreverse applied)
            report (nreverse report))
      ;; The data directory may have been renamed: re-resolve it.
      (let* ((declared (blueprint--version-read root))
             (remaining (blueprint--upgrade-pending root))
             (migrations (delete-dups (append (cdr declared) applied)))
             (version (if (cl-some (lambda (p) (plist-get (car p) :era))
                                   remaining)
                          (or (car declared)
                              (cl-some (lambda (p) (plist-get (car p) :era))
                                       remaining))
                        (blueprint-package-version))))
        (blueprint--version-write version migrations root))
      (when backup
        (with-temp-file (expand-file-name "report.org" backup)
          (insert "#+TITLE: Migrazione Blueprint\n\n"
                  (format "- Data: %s\n" (format-time-string "%Y-%m-%d %H:%M"))
                  (format "- Versione del pacchetto: %s\n\n" (blueprint-package-version))
                  "I file com'erano prima della migrazione sono in questa directory,\n"
                  "con lo stesso percorso relativo alla root del progetto.\n\n")
          (dolist (r report)
            (insert (format "* %s (%s)\n" (plist-get (car r) :title)
                            (plist-get (car r) :id)))
            (dolist (line (cdr r))
              (insert (format "- %s\n" line)))
            (insert "\n")))))
    (list :applied applied :report report :backup backup)))

;;; --- Plan buffer ---

(defvar blueprint-upgrade-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map "x" #'blueprint-upgrade-apply-at-point)
    (define-key map "X" #'blueprint-upgrade-apply-all)
    (define-key map "d" #'blueprint-upgrade-details-at-point)
    (define-key map (kbd "RET") #'blueprint-upgrade-details-at-point)
    (define-key map "g" #'blueprint-project-upgrade)
    map)
  "Keymap for `blueprint-upgrade-mode'.")

(define-derived-mode blueprint-upgrade-mode tabulated-list-mode
  "Blueprint Upgrade"
  "Major mode for the migration plan of a Blueprint project.
\\<blueprint-upgrade-mode-map>\\[blueprint-upgrade-apply-at-point] applies the step at point, or updates the stale
template at point; \\[blueprint-upgrade-apply-all] applies every pending step;
\\[blueprint-upgrade-details-at-point] shows the files of a step or the diff of a template;
\\[blueprint-project-upgrade] refreshes.  Nothing is applied without confirmation."
  (setq tabulated-list-format [("Tipo" 9 t) ("Passo / file" 34 t)
                               ("Da" 24 t) ("Descrizione" 60 nil)])
  (tabulated-list-init-header))

(defvar-local blueprint-upgrade--root nil
  "Project root of the plan buffer.")

(defun blueprint--upgrade-plan-entries (root)
  "Return the tabulated-list entries of the plan of ROOT."
  (let ((default-directory root))
    (append
     (mapcar (lambda (p)
               (let ((step (car p)))
                 (list (list 'step (plist-get step :id) (cdr p))
                       ;; A step that says nothing about the layout
                       ;; (version-file) has no :era, and
                       ;; tabulated-list needs a string in every column.
                       (vector "passo" (plist-get step :id)
                               (or (plist-get step :era) "--")
                               (format "%s (%d file)" (plist-get step :title)
                                       (length (cdr p)))))))
             (blueprint--upgrade-pending root))
     (mapcar (lambda (tpl)
               (pcase-let ((`(,scope ,file ,status) tpl))
                 (list (list 'template file status)
                       (vector "template"
                               (format "%s/%s" (if (eq scope 'user) "utente" "progetto")
                                       (file-name-nondirectory file))
                               (if (eq status 'stale) "versione precedente"
                                 "personalizzato")
                               (if (eq status 'stale)
                                   "Copia non modificata di una versione precedente: x la aggiorna (con backup)"
                                 "Diverso da ogni versione rilasciata: d mostra il diff, aggiornamento a mano")))))
             (blueprint--template-statuses root)))))

(defun blueprint--upgrade-header (root)
  "Return the header line of the plan of ROOT."
  (let* ((version (blueprint--project-version root))
         (git (and blueprint-upgrade-git-check (blueprint--upgrade-git-dirty-p root))))
    (format " Progetto: %s (%s) | Pacchetto: %s | Backup: %s%s"
            (car version)
            (if (eq (cdr version) 'declared) "dichiarata" "dedotta")
            (blueprint-package-version)
            (if blueprint-upgrade-backup blueprint-upgrade-backup-directory "disattivato")
            (if git " | git: modifiche non committate" ""))))

;;;###autoload
(defun blueprint-project-upgrade ()
  "Show the migration plan of the current Blueprint project.
The pending steps of `blueprint-upgrade-steps' (formats older versions
wrote, still read as they are) and the project and user template
copies that are older than the system ones or customized.  Nothing
changes until a step is applied from the buffer; the migration is
always optional."
  (interactive)
  (let ((root (file-name-as-directory
               (or (and (derived-mode-p 'blueprint-upgrade-mode) blueprint-upgrade--root)
                   (blueprint--root)))))
    (with-current-buffer (get-buffer-create "*Blueprint Upgrade*")
      (let ((default-directory root))
        (blueprint-upgrade-mode)
        (setq blueprint-upgrade--root root)
        (setq tabulated-list-entries (blueprint--upgrade-plan-entries root))
        (setq header-line-format (blueprint--upgrade-header root))
        (tabulated-list-print)
        (when (null tabulated-list-entries)
          (message "Nothing to migrate: the project is in the current format")))
      (switch-to-buffer (current-buffer)))))

(defun blueprint-upgrade-apply-at-point ()
  "Apply the step at point, or update the stale template at point."
  (interactive)
  (let ((id (tabulated-list-get-id))
        (root blueprint-upgrade--root))
    (pcase id
      (`(step ,step-id ,files)
       (when (yes-or-no-p (format "Apply %s (%d file, backup %s)? "
                                  step-id (length files)
                                  (if blueprint-upgrade-backup "on" "off")))
         (let ((result (blueprint-upgrade-apply (list step-id) root)))
           (message "Applied %s%s" step-id
                    (if (plist-get result :backup)
                        (format "; backup in %s"
                                (file-relative-name (plist-get result :backup) root))
                      "")))))
      (`(template ,file stale)
       (when (yes-or-no-p (format "Replace %s with the current system template? " file))
         (message "Template updated; old copy in %s" (blueprint--template-update file))))
      (`(template ,_file customized)
       (user-error "A customized template is not replaced: use d for the diff and merge by hand"))
      (_ (user-error "Nothing at point")))
    (let ((default-directory root)) (blueprint-project-upgrade))))

(defun blueprint-upgrade-apply-all ()
  "Apply every pending migration step of the plan.
Then offers to update the stale template copies too (customized ones
are never replaced)."
  (interactive)
  (let* ((root blueprint-upgrade--root)
         (stale (let ((default-directory root))
                  (cl-remove-if-not (lambda (tpl) (eq (nth 2 tpl) 'stale))
                                    (blueprint--template-statuses root)))))
    (when (and (let ((default-directory root)) (blueprint--upgrade-pending root))
               (yes-or-no-p (format "Apply every pending step (backup %s)? "
                                    (if blueprint-upgrade-backup "on" "off"))))
      (let ((result (blueprint-upgrade-apply nil root)))
        (message "Applied: %s%s"
                 (mapconcat #'identity (plist-get result :applied) ", ")
                 (if (plist-get result :backup)
                     (format "; backup in %s"
                             (file-relative-name (plist-get result :backup) root))
                   ""))))
    (when (and stale
               (yes-or-no-p (format "Also replace %d unmodified older template cop%s with the current ones (old copies kept)? "
                                    (length stale) (if (= 1 (length stale)) "y" "ies"))))
      (dolist (tpl stale) (blueprint--template-update (nth 1 tpl))))
    (let ((default-directory root)) (blueprint-project-upgrade))))

(defun blueprint-upgrade-details-at-point ()
  "Show the files of the step at point, or the diff of the template."
  (interactive)
  (let ((root blueprint-upgrade--root))
    (pcase (tabulated-list-get-id)
      (`(step ,step-id ,files)
       (message "%s: %s" step-id
                (mapconcat (lambda (f) (file-relative-name f root)) files ", ")))
      (`(template ,file ,_status) (blueprint--template-diff file))
      (_ (user-error "Nothing at point")))))

(provide 'blueprint-upgrade)
;;; blueprint-upgrade.el ends here
