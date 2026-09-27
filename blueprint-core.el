;;; blueprint-core.el --- Core utilities for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Project root detection, component enumeration, template resolution
;; (three-tier: project > user > system), and initialization commands.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-element)

(defgroup blueprint nil
  "Text-first architectural assessment toolkit."
  :group 'tools
  :prefix "blueprint-")

(defcustom blueprint-template-dir
  (expand-file-name "templates"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory containing system-level Blueprint templates."
  :type 'directory
  :group 'blueprint)

(defcustom blueprint-user-template-dir
  (expand-file-name "~/.config/blueprint/templates")
  "Directory containing user-level Blueprint templates."
  :type 'directory
  :group 'blueprint)

(defconst blueprint--org-file-regexp "\\`[^.#].*\\.org\\'"
  "Regexp matching the Org files Blueprint scans in a directory tree.
Excludes names starting with \".\" or \"#\": Emacs lock files
\(\".#foo.org\", a dangling symlink while foo.org has unsaved changes)
otherwise pass a plain \".org\" suffix test and make
`insert-file-contents' fail.")

(defconst blueprint--legacy-directory-name ".blueprint"
  "Project data directory name used before `blueprint-directory-name' existed.
Projects still using it keep working; `blueprint-migrate-directory'
renames it to the configured name.")

(defun blueprint--valid-directory-name-p (name)
  "Return non-nil if NAME is usable as `blueprint-directory-name'.
NAME must be a non-empty relative path with no \"..\" or \".\" segment,
so that the data directory always lives under the project root."
  (and (stringp name)
       (not (string-empty-p name))
       (not (file-name-absolute-p name))
       (let ((segments (split-string (directory-file-name name) "/")))
         (and segments
              (not (cl-some (lambda (s) (member s '("" "." ".."))) segments))))))

(defcustom blueprint-directory-name blueprint--legacy-directory-name
  "Name of the per-project data directory, relative to the project root.
It holds components, ADRs and project-local templates.  It may be a
nested relative path (e.g. \"content/blueprint\") so that the layout
matches what an external site generator or build tool expects.

A project whose data directory is still called \".blueprint\" keeps
working after this is changed; run `blueprint-migrate-directory' to
rename it."
  :type 'string
  :safe #'blueprint--valid-directory-name-p
  :group 'blueprint)

(defun blueprint--directory-name ()
  "Return `blueprint-directory-name', signaling an error if invalid."
  (unless (blueprint--valid-directory-name-p blueprint-directory-name)
    (user-error "Invalid `blueprint-directory-name': %S (must be a relative path inside the project)"
                blueprint-directory-name))
  (directory-file-name blueprint-directory-name))

(defvar blueprint--warned-roots (make-hash-table :test 'equal)
  "Project roots already warned about their data directory this session.
Keeps `blueprint--root', which runs on every command and save hook,
from repeating the same warning.")

(defun blueprint--warn-once (root fmt &rest args)
  "Display warning FMT with ARGS once per session for project ROOT."
  (unless (gethash root blueprint--warned-roots)
    (puthash root t blueprint--warned-roots)
    (display-warning 'blueprint (apply #'format fmt args) :warning)))

(defun blueprint--has-data-dir-p (dir)
  "Return non-nil if DIR contains the configured or the legacy data directory."
  (or (file-directory-p (expand-file-name (blueprint--directory-name) dir))
      (file-directory-p (expand-file-name blueprint--legacy-directory-name dir))))

(defun blueprint--data-dir (&optional root)
  "Return the absolute data directory of the project at ROOT.
ROOT defaults to `blueprint--root'.  Returns the configured directory
\(`blueprint-directory-name') when it exists, else the legacy
\".blueprint\" directory when that exists, else the configured one
\(for a project not initialized yet)."
  (let* ((root (or root (blueprint--root)))
         (configured (expand-file-name (blueprint--directory-name) root))
         (legacy (expand-file-name blueprint--legacy-directory-name root)))
    (cond ((file-directory-p configured) configured)
          ((file-directory-p legacy) legacy)
          (t configured))))

(defun blueprint--data-path (relative &optional root)
  "Return RELATIVE expanded inside the data directory of ROOT."
  (expand-file-name relative (blueprint--data-dir root)))

(defun blueprint--root ()
  "Return the root directory of the current Blueprint project.
The root is the nearest ancestor of `default-directory' that contains
either the configured data directory (`blueprint-directory-name') or
the legacy \".blueprint\" one.  Signals an error if there is none."
  (let ((root (locate-dominating-file default-directory
                                      #'blueprint--has-data-dir-p)))
    (unless root
      (user-error "Not in a Blueprint project (no %s directory found)"
                  (blueprint--directory-name)))
    (let ((configured (blueprint--directory-name)))
      (unless (string= configured blueprint--legacy-directory-name)
        (let ((has-new (file-directory-p (expand-file-name configured root)))
              (has-old (file-directory-p
                        (expand-file-name blueprint--legacy-directory-name root))))
          (cond
           ((and has-new has-old)
            (blueprint--warn-once
             root "Project %s has both %s/ and %s/; using %s/.  Merge them by hand"
             root configured blueprint--legacy-directory-name configured))
           (has-old
            (blueprint--warn-once
             root "Project %s still uses %s/; run `blueprint-migrate-directory' to rename it to %s/"
             root blueprint--legacy-directory-name configured))))))
    root))

(defun blueprint--init-file (path template-name replacements)
  "Create PATH from TEMPLATE-NAME applying REPLACEMENTS, unless PATH exists.
REPLACEMENTS is an alist of (PLACEHOLDER . VALUE) string pairs."
  (unless (file-exists-p path)
    (let ((content (blueprint--template template-name)))
      (dolist (pair replacements)
        (setq content (replace-regexp-in-string
                       (regexp-quote (car pair)) (cdr pair) content t t)))
      (make-directory (file-name-directory path) t)
      (with-temp-file path
        (insert content)))))

(defun blueprint--provision-user-templates ()
  "Copy system templates to the user template directory if they do not exist.

This function is called automatically on `blueprint-init' to ensure that
user-level templates are available for customisation.

IMPORTANT -- FILES WRITTEN TO YOUR HOME DIRECTORY:
This function writes template files to `blueprint-user-template-dir',
which defaults to `~/.config/blueprint/templates/'.  These become your
personal defaults that apply across all Blueprint projects.

You can edit them freely.  Blueprint will NEVER overwrite them once
created.  To revert a template to the system default, delete the file
from `~/.config/blueprint/templates/' -- Blueprint will then fall back
to the version bundled with the package."
  (let ((user-dir blueprint-user-template-dir)
        (sys-dir blueprint-template-dir)
        (copied '()))
    (unless (file-directory-p user-dir)
      (make-directory user-dir t))
    (dolist (f (directory-files sys-dir t "\\.org\\'"))
      (let ((target (expand-file-name (file-name-nondirectory f) user-dir)))
        (unless (file-exists-p target)
          (copy-file f target)
          (push (file-name-nondirectory f) copied))))
    (when copied
      (message
       (concat "Blueprint: wrote %d template(s) to %s\n"
               "  %s\n"
               "These are your personal defaults.  "
               "Edit freely -- Blueprint will never overwrite them.")
       (length copied)
       user-dir
       (mapconcat (lambda (f) (format "  - %s" f)) copied "\n")))))

;;;###autoload
(defun blueprint-init (&optional project-name author)
  "Initialize a new Blueprint project in the current directory.

PROJECT-NAME is the client/project name used in `master.org'.
AUTHOR is used as the document author.  Both default to sensible values
when called non-interactively.

On the first run, this command also provisions user-level templates to
`~/.config/blueprint/templates/' (see `blueprint--provision-user-templates').
You will see a message listing the files written to your home directory.

Creates the following structure (the data directory is named after
`blueprint-directory-name', default \".blueprint\"):

  .blueprint/
    components/   -- one subdirectory per component (arc42.org, etc.)
    adr/          -- Architecture Decision Records
    templates/    -- project-local template overrides (initially empty)
  enterprise/
    context.org   -- C4 L1 multi-system context diagram
    dependencies.org  -- dependency matrix and cross-system flows
  nfr/
    quality-scenarios.org
    constraints.org
    risks.org
  _archive/       -- archived (removed) components
  master.org      -- main document, assembles all parts with #+INCLUDE
  glossary.org    -- standalone glossary, linkable from any file
  references.org  -- document, interview, and system references"
  (interactive
   (list (read-string
          "Project/client name: "
          (file-name-nondirectory (directory-file-name default-directory)))
         (read-string "Author name: " (user-full-name))))
  (let* ((root default-directory)
         (bp (blueprint--data-dir root))
         (pname (or project-name
                    (file-name-nondirectory (directory-file-name root))))
         (pauthor (or author (user-full-name)))
         (date (format-time-string "%Y-%m-%d"))
         (replacements `(("{{PROJECT}}" . ,pname)
                         ("{{AUTHOR}}"  . ,pauthor)
                         ("{{DATE}}"    . ,date))))
    ;; 1. Data directory internals
    (dolist (d (list bp
                     (expand-file-name "components" bp)
                     (expand-file-name "adr" bp)
                     (expand-file-name "templates" bp)))
      (make-directory d t))
    ;; 2. Provision user-level templates (interactive only, never in tests)
    (when (called-interactively-p 'interactive)
      (blueprint--provision-user-templates))
    ;; 3. Project top-level directories
    (dolist (d (list (expand-file-name "enterprise" root)
                     (expand-file-name "nfr" root)
                     (expand-file-name "_archive" root)))
      (make-directory d t))
    ;; 4. Populate project files from templates (skips files that already exist)
    (blueprint--init-file (expand-file-name "master.org" root)
                          "master.org" replacements)
    (blueprint--init-file (expand-file-name "glossary.org" root)
                          "glossary.org" replacements)
    (blueprint--init-file (expand-file-name "references.org" root)
                          "references.org" replacements)
    (blueprint--init-file (expand-file-name "enterprise/context.org" root)
                          "enterprise-context.org" replacements)
    (blueprint--init-file (expand-file-name "enterprise/dependencies.org" root)
                          "enterprise-dependencies.org" replacements)
    (blueprint--init-file (expand-file-name "nfr/quality-scenarios.org" root)
                          "nfr-quality.org" replacements)
    (blueprint--init-file (expand-file-name "nfr/constraints.org" root)
                          "nfr-constraints.org" replacements)
    (blueprint--init-file (expand-file-name "nfr/risks.org" root)
                          "nfr-risks.org" replacements)
    (message "Blueprint project '%s' initialized in %s" pname root)))

(defun blueprint--components ()
  "Return a hash table mapping component names to their directories."
  (let* ((dir (blueprint--data-path "components"))
         (tbl (make-hash-table :test 'equal)))
    (when (file-exists-p dir)
      (dolist (d (directory-files dir t "^[^.]"))
        (when (file-directory-p d)
          (puthash (file-name-nondirectory d) d tbl))))
    tbl))

(defun blueprint--component-file (id)
  "Return the path to the arc42.org file for component ID."
  (let ((dir (gethash id (blueprint--components))))
    (when dir
      (expand-file-name "arc42.org" dir))))

;;; --- Org keywords ---

(defvar blueprint--org-keyword-cache (make-hash-table :test 'equal)
  "Cache for `blueprint--org-keyword': (FILE . KEY) -> (STAMP . VALUE).
STAMP is FILE's modification time and size, so an edited file is
re-read.  Lint, risks and dashboard read the same keywords of every
component repeatedly (risks once per pair of components).")

(defun blueprint--file-stamp (file)
  "Return FILE's modification time and size, or nil if it has none."
  (let ((attrs (file-attributes file)))
    (when attrs
      (cons (file-attribute-modification-time attrs)
            (file-attribute-size attrs)))))

(defun blueprint--org-keyword-1 (file key)
  "Read the first non-empty Org keyword KEY in FILE, uncached."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((org-inhibit-startup t))
      (delay-mode-hooks (org-mode)))
    (goto-char (point-min))
    (let ((re (format "^[ \t]*#\\+%s:" (regexp-quote key)))
          (case-fold-search t)
          value)
      (while (and (not value) (re-search-forward re nil t))
        (let ((el (save-excursion (beginning-of-line) (org-element-at-point))))
          (when (eq (org-element-type el) 'keyword)
            (let ((v (string-trim (org-element-property :value el))))
              (unless (string-empty-p v) (setq value v))))))
      value)))

(defun blueprint--org-keyword (file key)
  "Return the value of the first Org keyword KEY in FILE, or nil.
KEY is matched case-insensitively.  An empty value counts as absent,
so an unfilled \"#+BLUEPRINT_DEPENDS:\" yields nil.  FILE may be nil
or missing (returns nil).

Candidate lines are found with a regex, but each is confirmed with
`org-element-at-point': a regex alone also matches keyword lines
shown as examples inside src/example blocks (the templates'
:noexport: guides contain some), and the old \"\\s-*\" pattern
crossed newlines, so an empty keyword returned the next line.
Results are cached per file until it changes."
  (when (and file (file-exists-p file))
    (let* ((file (expand-file-name file))
           (stamp (blueprint--file-stamp file))
           (cache-key (cons file (upcase key)))
           (hit (gethash cache-key blueprint--org-keyword-cache)))
      (if (and hit (equal (car hit) stamp))
          (cdr hit)
        (let ((value (blueprint--org-keyword-1 file key)))
          (puthash cache-key (cons stamp value) blueprint--org-keyword-cache)
          value)))))

;;; --- Countable text (markers outside non-exported content) ---

(defun blueprint--insert-org-file (file)
  "Insert FILE into the current buffer and turn on `org-mode' quietly."
  (insert-file-contents file)
  (let ((org-inhibit-startup t))
    (delay-mode-hooks (org-mode))))

(defun blueprint--export-exclude-tags (tree)
  "Return the export exclude tags in effect for parse TREE.
`org-export-exclude-tags' (default \"noexport\") plus the values of the
buffer's #+EXCLUDE_TAGS: keywords."
  (flatten-tree
   (append (if (boundp 'org-export-exclude-tags)
               org-export-exclude-tags
             '("noexport"))
           (org-element-map tree 'keyword
             (lambda (kw)
               (when (string= (org-element-property :key kw) "EXCLUDE_TAGS")
                 (split-string (org-element-property :value kw))))))))

(defun blueprint--excluded-headline-p (headline exclude)
  "Return non-nil if HEADLINE is left out of the export.
That is, it is COMMENTed or carries one of the tags in EXCLUDE."
  (or (org-element-property :commentedp headline)
      (cl-intersection (org-element-property :tags headline) exclude
                       :test #'string=)))

(defun blueprint--non-exported-subtrees (&optional tree)
  "Return (BEG . END) of each subtree the export leaves out.
TREE defaults to a parse of the current buffer.  Sorted by BEG."
  (let* ((tree (or tree (org-element-parse-buffer 'headline)))
         (exclude (blueprint--export-exclude-tags tree))
         (regions '()))
    (org-element-map tree 'headline
      (lambda (hl)
        (when (blueprint--excluded-headline-p hl exclude)
          (push (cons (org-element-property :begin hl)
                      (org-element-property :end hl))
                regions))))
    (sort regions (lambda (a b) (< (car a) (car b))))))

(defun blueprint--uncounted-regions ()
  "Return the regions of the current Org buffer where markers do not count.
A list of (BEG . END), sorted by BEG.  Markers are counted only in
what the export shows as live text, so these are excluded:

- subtrees tagged with an export exclude tag (`org-export-exclude-tags',
  default \"noexport\", plus the file's #+EXCLUDE_TAGS:) or COMMENTed,
  which is where the templates keep their fictional example data;
- src, example, export and comment blocks, fixed-width areas and
  comment lines;
- verbatim and code objects (=[FINDING]= names the marker, it is not one).

Keywords such as #+STATUS: [DA VALIDARE] are not excluded: they
mark the whole file as not yet validated."
  (let ((tree (org-element-parse-buffer 'object))
        (regions '()))
    (org-element-map tree '(src-block example-block export-block
                            comment-block fixed-width comment verbatim code)
      (lambda (el)
        (push (cons (org-element-property :begin el)
                    (org-element-property :end el))
              regions)))
    (sort (append (blueprint--non-exported-subtrees tree) regions)
          (lambda (a b) (< (car a) (car b))))))

(defun blueprint--in-regions-p (pos regions)
  "Return non-nil if POS lies in one of REGIONS, a list of (BEG . END)."
  (cl-some (lambda (r) (and (>= pos (car r)) (< pos (cdr r)))) regions))

(defun blueprint--marker-positions (regexp &optional regions)
  "Return the start of each REGEXP match in the buffer outside REGIONS.
REGIONS defaults to `blueprint--uncounted-regions'.  The buffer must
be in `org-mode' (see `blueprint--insert-org-file')."
  (let ((regions (or regions (blueprint--uncounted-regions)))
        (case-fold-search nil)
        (found '()))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward regexp nil t)
        (unless (blueprint--in-regions-p (match-beginning 0) regions)
          (push (match-beginning 0) found))))
    (nreverse found)))

(defun blueprint--count-file-markers (file regexps)
  "Count each regexp of REGEXPS in FILE, outside uncounted regions.
Returns a list of counts in the order of REGEXPS, or zeros if FILE is
nil or missing."
  (if (and file (file-exists-p file))
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (let ((regions (blueprint--uncounted-regions)))
          (mapcar (lambda (re) (length (blueprint--marker-positions re regions)))
                  regexps)))
    (make-list (length regexps) 0)))

;;; --- Metrics cache ---

(defvar blueprint--metrics-cache (make-hash-table :test 'equal)
  "Hash table mapping file paths to (HASH . METRICS) cons cells.")

(defun blueprint--file-hash (file)
  "Return a hash string for the contents of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (secure-hash 'md5 (buffer-string))))

(defun blueprint--cached-metrics (file metrics-fn)
  "Return cached metrics for FILE, recomputing via METRICS-FN if stale."
  (if (and file (file-exists-p file))
      (let* ((current-hash (blueprint--file-hash file))
             (cached (gethash file blueprint--metrics-cache))
             (cached-hash (car cached)))
        (if (equal current-hash cached-hash)
            (cdr cached)
          (let ((metrics (funcall metrics-fn file)))
            (puthash file (cons current-hash metrics) blueprint--metrics-cache)
            metrics)))
    (funcall metrics-fn file)))

(defun blueprint--invalidate-cache (&optional file)
  "Invalidate metrics cache for FILE, or all entries if FILE is nil."
  (if file
      (let ((abs (expand-file-name file)))
        (remhash file blueprint--metrics-cache)
        ;; Stamps alone miss a same-size edit within one mtime tick on
        ;; coarse-mtime filesystems (FAT, some network mounts).
        (dolist (k (hash-table-keys blueprint--org-keyword-cache))
          (when (equal (car k) abs)
            (remhash k blueprint--org-keyword-cache))))
    (clrhash blueprint--metrics-cache)
    (clrhash blueprint--org-keyword-cache)))

(defun blueprint--cache-hook ()
  "Hook function to invalidate cache for the current buffer's file."
  (when buffer-file-name
    (blueprint--invalidate-cache buffer-file-name)))

;;; --- Component CRUD ---

;;;###autoload
(defun blueprint-list-components ()
  "Display a list of all components in the current Blueprint project."
  (interactive)
  (let ((comps (blueprint--components))
        (entries '()))
    (maphash (lambda (id dir)
               (push (list id (vector id (abbreviate-file-name dir))) entries))
             comps)
    (if (null entries)
        (message "No components found.")
      (with-current-buffer (get-buffer-create "*Blueprint Components*")
        (setq tabulated-list-format [("Component" 30 t) ("Directory" 60 t)]
              tabulated-list-entries entries)
        (tabulated-list-mode)
        (tabulated-list-init-header)
        (tabulated-list-print)
        (local-set-key (kbd "RET")
                       (lambda ()
                         (interactive)
                         (let ((id (tabulated-list-get-id)))
                           (when id
                             (find-file (blueprint--component-file id))))))
        (switch-to-buffer (current-buffer))))))

(defun blueprint--rename-dependency (file old-name new-name)
  "Replace dependency OLD-NAME with NEW-NAME in FILE's #+BLUEPRINT_DEPENDS:.
Only whole whitespace-separated tokens match: component ids contain
hyphens, which `\\b' treats as word boundaries, so a regex rename of
\"auth\" also rewrote \"auth-db\".  Keywords are located with
`org-element', so example lines inside src blocks are left alone.
Writes FILE only when something changed."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((org-inhibit-startup t))
      (delay-mode-hooks (org-mode)))
    (let ((edits '()))
      (org-element-map (org-element-parse-buffer 'element) 'keyword
        (lambda (kw)
          (when (string= (org-element-property :key kw) "BLUEPRINT_DEPENDS")
            (let* ((tokens (split-string (org-element-property :value kw)))
                   (new (mapcar (lambda (d) (if (string= d old-name) new-name d))
                                tokens)))
              (unless (equal tokens new)
                (push (cons (org-element-property :begin kw)
                            (mapconcat #'identity new " "))
                      edits))))))
      ;; `edits' is already back-to-front: later keywords were pushed last.
      (dolist (e edits)
        (goto-char (car e))
        (when (re-search-forward "BLUEPRINT_DEPENDS:[[:blank:]]*\\(.*\\)$"
                                 (line-end-position) t)
          (replace-match (cdr e) t t nil 1)))
      (when edits
        (write-region (point-min) (point-max) file nil 'silent)))))

;;;###autoload
(defun blueprint-rename-component (old-name new-name)
  "Rename component OLD-NAME to NEW-NAME.
Updates the directory name and BLUEPRINT_DEPENDS references in all components."
  (interactive
   (let* ((comps (blueprint--components))
          (names (hash-table-keys comps)))
     (list (completing-read "Rename component: " names nil t)
           (read-string "New name: "))))
  (let* ((comps (blueprint--components))
         (old-dir (gethash old-name comps)))
    (unless old-dir
      (user-error "Component %s not found" old-name))
    (let ((new-dir (expand-file-name new-name (file-name-directory old-dir))))
      (rename-file old-dir new-dir)
      ;; Update TITLE in the renamed component's arc42.org
      (let ((arc-file (expand-file-name "arc42.org" new-dir)))
        (when (file-exists-p arc-file)
          (with-temp-buffer
            (insert-file-contents arc-file)
            (goto-char (point-min))
            (when (re-search-forward (format "^#\\+TITLE:.*%s" (regexp-quote old-name)) nil t)
              (replace-match (format "#+TITLE: %s" new-name)))
            (write-region (point-min) (point-max) arc-file))))
      ;; Update BLUEPRINT_DEPENDS in all other components
      (maphash
       (lambda (_id dir)
         (let ((file (expand-file-name "arc42.org" dir)))
           (when (file-exists-p file)
             (blueprint--rename-dependency file old-name new-name))))
       (blueprint--components))
      (blueprint--invalidate-cache)
      (message "Renamed %s → %s" old-name new-name))))

;;;###autoload
(defun blueprint-delete-component (name)
  "Delete component NAME from the current Blueprint project.
Prompts for confirmation before deleting."
  (interactive
   (let* ((comps (blueprint--components))
          (names (hash-table-keys comps)))
     (list (completing-read "Delete component: " names nil t))))
  (let* ((comps (blueprint--components))
         (dir (gethash name comps)))
    (unless dir
      (user-error "Component %s not found" name))
    (when (yes-or-no-p (format "Really delete component %s and all its files? " name))
      (delete-directory dir t)
      (blueprint--invalidate-cache)
      (message "Deleted component %s" name))))

(defun blueprint--project-template-dir ()
  "Return the path to the project-level templates directory."
  (blueprint--data-path "templates"))

(defun blueprint--resolve-template (name)
  "Resolve template NAME by searching project, user, and system directories.
Returns the first matching path, or nil if not found."
  (cl-loop for d in (list (blueprint--project-template-dir)
                          blueprint-user-template-dir
                          blueprint-template-dir)
           for p = (expand-file-name name d)
           when (file-exists-p p) return p))

(defun blueprint--template (name)
  "Return the contents of template NAME as a string."
  (let ((path (blueprint--resolve-template name)))
    (unless path
      (user-error "Template %s not found" name))
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

;;;###autoload
(defun blueprint-add-component (name)
  "Add a new component NAME to the current Blueprint project.
Creates the component directory under the data directory's
components/ (see `blueprint-directory-name') and
populates it from templates:
  - arc42.org         from component.org template
  - functional.org    from functional.org template (if available)
  - infrastructure.org from infrastructure.org template (if available)

Template placeholders replaced:
  {{NAME}} -- component display name as entered
  {{ID}}   -- slugified name (lowercase, hyphens) for diagram IDs
  {{DATE}} -- current date (YYYY-MM-DD)"
  (interactive "sComponent name: ")
  (let* ((id (replace-regexp-in-string "[^a-zA-Z0-9-]" "-" (downcase name)))
         (dir (expand-file-name id
                                (blueprint--data-path "components")))
         (date (format-time-string "%Y-%m-%d"))
         (replacements `(("{{NAME}}" . ,name)
                         ("{{ID}}"   . ,id)
                         ("{{DATE}}" . ,date))))
    ;; `make-directory' with PARENTS=t does not signal an error when DIR
    ;; already exists, so without this check adding a component whose
    ;; slugified id collides with an existing one (same name typed
    ;; twice, or two names that slugify the same, e.g. "Order Service"
    ;; and "order-service") would silently overwrite its arc42.org/
    ;; functional.org/infrastructure.org back to the blank template --
    ;; no error, no confirmation, no warning.
    (when (gethash id (blueprint--components))
      (user-error "Component \"%s\" already exists" id))
    (make-directory dir t)
    ;; arc42.org -- always created
    (let ((content (blueprint--template "component.org")))
      (dolist (pair replacements)
        (setq content (replace-regexp-in-string
                       (regexp-quote (car pair)) (cdr pair) content t t)))
      (with-temp-file (expand-file-name "arc42.org" dir)
        (insert content)))
    ;; functional.org -- created when template is available
    (when (blueprint--resolve-template "functional.org")
      (let ((content (blueprint--template "functional.org")))
        (dolist (pair replacements)
          (setq content (replace-regexp-in-string
                         (regexp-quote (car pair)) (cdr pair) content t t)))
        (with-temp-file (expand-file-name "functional.org" dir)
          (insert content))))
    ;; infrastructure.org -- created when template is available
    (when (blueprint--resolve-template "infrastructure.org")
      (let ((content (blueprint--template "infrastructure.org")))
        (dolist (pair replacements)
          (setq content (replace-regexp-in-string
                         (regexp-quote (car pair)) (cdr pair) content t t)))
        (with-temp-file (expand-file-name "infrastructure.org" dir)
          (insert content))))
    (find-file (expand-file-name "arc42.org" dir))))

(provide 'blueprint-core)
;;; blueprint-core.el ends here
