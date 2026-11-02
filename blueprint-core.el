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
(require 'tabulated-list)
(require 'lisp-mnt)

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

;;; --- Package and project version (see blueprint-upgrade.el) ---

(defconst blueprint--package-dir
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory holding the Blueprint sources.")

(defvar blueprint--package-version-cache nil
  "Cached result of `blueprint-package-version'.")

(defun blueprint-package-version ()
  "Return the version of the installed Blueprint package, as a string.
Read from the Version: header of blueprint.el, the one the release
workflow tags, so there is a single source.  \"unknown\" when the file
cannot be read."
  (or blueprint--package-version-cache
      (setq blueprint--package-version-cache
            (let ((main (expand-file-name "blueprint.el"
                                          blueprint--package-dir)))
              (or (and (file-readable-p main)
                       (with-temp-buffer
                         (insert-file-contents main)
                         (lm-header "Version")))
                  "unknown")))))

(defconst blueprint-version-file-name "blueprint-version.org"
  "Name of the file, in the data directory, holding the project version.")

(defun blueprint--version-file (&optional root)
  "Return the path of the project version file of ROOT."
  (blueprint--data-path blueprint-version-file-name root))

(defun blueprint--version-read (&optional root)
  "Return (VERSION . MIGRATIONS) declared by the project at ROOT, or nil.
VERSION is the #+BLUEPRINT_VERSION: value, MIGRATIONS the list of step
ids in #+BLUEPRINT_MIGRATIONS:.  nil when the file does not exist."
  (let ((file (blueprint--version-file root)))
    (when (file-exists-p file)
      (cons (blueprint--org-keyword file "BLUEPRINT_VERSION")
            (let ((m (blueprint--org-keyword file "BLUEPRINT_MIGRATIONS")))
              (and m (split-string m)))))))

(defun blueprint--version-write (version migrations &optional root)
  "Write the project version file of ROOT with VERSION and MIGRATIONS.
MIGRATIONS is the list of step ids applied to the project.  Returns
the file path."
  (let ((file (blueprint--version-file root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert "#+TITLE: Versione Blueprint del progetto\n"
              (format "#+BLUEPRINT_VERSION: %s\n" version)
              (format "#+BLUEPRINT_MIGRATIONS:%s\n"
                      (if migrations
                          (concat " " (mapconcat #'identity migrations " "))
                        ""))
              "\n"
              "File gestito da Blueprint: la versione del pacchetto con cui il\n"
              "progetto è stato creato o aggiornato e le migrazioni applicate\n"
              "da `blueprint-project-upgrade'.  Non è incluso in master.org e\n"
              "non è obbligatorio: senza, la versione viene dedotta dai file.\n"))
    (blueprint--invalidate-cache file)
    file))

(defun blueprint--version-record-init (&optional root)
  "Record the current package version for a new project at ROOT.
Called by `blueprint-init'; never overwrites an existing file, so a
re-run of `blueprint-init' on an old project does not claim it is
up to date."
  (unless (file-exists-p (blueprint--version-file root))
    (blueprint--version-write (blueprint-package-version) nil root)))

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

(defun blueprint--copy-file-writable (file newname)
  "Copy FILE to NEWNAME and make the copy writable by its owner.
`copy-file' keeps the source's permission bits, and the system
templates can be read-only (package installed by Nix, a distribution
package or any read-only store): without this the \"editable\" copies
in the user or project template directory could not be edited."
  (copy-file file newname)
  (set-file-modes newname (logior (or (file-modes newname) #o444) #o200)))

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
          (blueprint--copy-file-writable f target)
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
    ;; 5. Version of the project layout (never overwritten: re-running
    ;; init on an old project must not claim it is up to date).
    (blueprint--version-record-init root)
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

(defconst blueprint--component-document-files
  '("arc42.org" "functional.org" "infrastructure.org")
  "Files of a component that `blueprint-sync' includes in master.org.
arc42.org goes to Parte II, functional.org to Parte III and
infrastructure.org to Parte IV.  Only arc42.org is mandatory.")

(defun blueprint--component-document-paths (id)
  "Return the existing files of component ID that reach the document.
See `blueprint--component-document-files'.  Absent files are left out."
  (let ((dir (gethash id (blueprint--components))))
    (when dir
      (cl-loop for name in blueprint--component-document-files
               for path = (expand-file-name name dir)
               when (file-exists-p path) collect path))))

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

(defun blueprint--merge-regions (regions)
  "Merge REGIONS, a list of (BEG . END) sorted by BEG, into disjoint ones.
Uncounted regions nest (a verbatim object inside a :noexport: subtree)."
  (let ((merged '()))
    (dolist (r regions)
      (if (and merged (<= (car r) (cdar merged)))
          (setcdr (car merged) (max (cdr r) (cdar merged)))
        (push (cons (car r) (cdr r)) merged)))
    (nreverse merged)))

(defun blueprint--count-words-outside (&optional regions)
  "Return the number of words in the current buffer outside REGIONS.
REGIONS defaults to `blueprint--uncounted-regions', so the result is
the size of the text the export shows, measured with `count-words'.
The buffer must be in `org-mode' (see `blueprint--insert-org-file')."
  (let ((pos (point-min))
        (words 0))
    (dolist (r (blueprint--merge-regions
                (or regions (blueprint--uncounted-regions))))
      (when (> (car r) pos)
        (cl-incf words (count-words pos (min (car r) (point-max)))))
      (setq pos (max pos (cdr r))))
    (when (< pos (point-max))
      (cl-incf words (count-words pos (point-max))))
    words))

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

(defun blueprint--cached-metrics (file metrics-fn &optional kind)
  "Return cached metrics for FILE, recomputing via METRICS-FN if stale.
The cache is keyed by FILE alone, not by METRICS-FN: callers that
store a different kind of data for the same file pass a symbol KIND,
and the entry is then keyed by (FILE . KIND).  Without KIND the key
is FILE, which holds the technical marker counts of
`blueprint--component-metrics' (dashboard, graph, daily and risks
used to share it for arc42.org)."
  (if (and file (file-exists-p file))
      (let* ((key (if kind (cons file kind) file))
             (current-hash (blueprint--file-hash file))
             (cached (gethash key blueprint--metrics-cache))
             (cached-hash (car cached)))
        (if (equal current-hash cached-hash)
            (cdr cached)
          (let ((metrics (funcall metrics-fn file)))
            (puthash key (cons current-hash metrics) blueprint--metrics-cache)
            metrics)))
    (funcall metrics-fn file)))

(defun blueprint--invalidate-cache (&optional file)
  "Invalidate metrics cache for FILE, or all entries if FILE is nil.
For FILE this drops both the plain entry and every (FILE . KIND)
entry (see `blueprint--cached-metrics')."
  (if file
      (let ((abs (expand-file-name file)))
        (remhash file blueprint--metrics-cache)
        (dolist (k (hash-table-keys blueprint--metrics-cache))
          (when (and (consp k) (equal (car k) file))
            (remhash k blueprint--metrics-cache)))
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

;;; --- Graphviz ---

(defun blueprint--dot-id (id)
  "Return ID as a quoted Graphviz identifier.
An unquoted DOT identifier allows only letters, digits and
underscores, while component ids are slugs with hyphens
\(\"order-service\"): unquoted, `dot' stops with a syntax error."
  (concat "\"" (replace-regexp-in-string "[\"\\]" "\\\\\\&" id) "\""))

(defun blueprint--dot-render (dot-file svg-file)
  "Render DOT-FILE to SVG-FILE with Graphviz and delete DOT-FILE.
Signals an error with the output of `dot' when it fails, instead of
returning the path of an SVG that was not written (or is stale)."
  (with-temp-buffer
    (let ((exit (call-process "dot" nil t nil "-Tsvg" "-o" svg-file dot-file)))
      (unless (eq exit 0)
        (error "Graphviz failed on %s (exit %s): %s"
               dot-file exit (string-trim (buffer-string))))))
  (delete-file dot-file)
  svg-file)

;;; --- Master sync markers (shared with blueprint-sync) ---

(defvar blueprint-sync-start-marker "# @@blueprint-sync-start@@"
  "Marker that begins the auto-generated arc42 include section.")

(defvar blueprint-sync-end-marker "# @@blueprint-sync-end@@"
  "Marker that ends the auto-generated arc42 include section.")

(defvar blueprint-sync-functional-start-marker
  "# @@blueprint-sync-functional-start@@"
  "Marker that begins the auto-generated functional spec include section.")

(defvar blueprint-sync-functional-end-marker
  "# @@blueprint-sync-functional-end@@"
  "Marker that ends the auto-generated functional spec include section.")

(defvar blueprint-sync-infra-start-marker
  "# @@blueprint-sync-infra-start@@"
  "Marker that begins the auto-generated infrastructure include section.")

(defvar blueprint-sync-infra-end-marker
  "# @@blueprint-sync-infra-end@@"
  "Marker that ends the auto-generated infrastructure include section.")

;;; --- Document files (master.org and what it includes) ---

(defun blueprint--master-file (&optional root)
  "Return the path to the master.org file of the project at ROOT.
ROOT defaults to `blueprint--root'."
  (expand-file-name "master.org" (or root (blueprint--root))))

(defun blueprint--parse-include-value (value dir)
  "Parse VALUE, the value of an #+INCLUDE: keyword in a file in DIR.
Returns a plist:
  :path     the included file, absolute, resolved against DIR (the
            directory of the including file, as the Org exporter does),
            without any \"::search\" suffix;
  :block    non-nil when the file is included as a block (\"src\",
            \"example\", \"export\" or any other block name): its
            content is then not live text;
  :partial  non-nil when only a part of the file is included
            (\":lines\" option or \"::search\" suffix).
Returns nil when VALUE names no file.  Options with a value such as
\":minlevel 3\" do not change the included text and are ignored."
  (when (string-match "\\`[ \t]*\\(\"\\(?:[^\"\\]\\|\\\\.\\)*\"\\|<[^>]*>\\|[^ \t]+\\)"
                      value)
    (let* ((raw (match-string 1 value))
           (rest (substring value (match-end 0)))
           (file (if (memq (aref raw 0) '(?\" ?<)) (substring raw 1 -1) raw))
           (search nil))
      (when (string-match "::\\(.*\\)\\'" file)
        (setq search (match-string 1 file)
              file (substring file 0 (match-beginning 0))))
      (unless (string-empty-p file)
        (let ((words (split-string
                      (replace-regexp-in-string
                       ":[[:alnum:]-]+[ \t]+\\(\"[^\"]*\"\\|[^ \t]+\\)" "" rest))))
          (list :path (expand-file-name file dir)
                :block (and words t)
                :partial (and (or search (string-match-p ":lines\\>" rest)) t)))))))

(defun blueprint--file-includes (file)
  "Return the #+INCLUDE: keywords of FILE that reach the export.
A list of plists, see `blueprint--parse-include-value', in file
order.  Keywords inside a subtree the export leaves out (see
`blueprint--non-exported-subtrees') are skipped; commented lines and
lines inside blocks are not keywords for `org-element' to begin with."
  (with-temp-buffer
    (blueprint--insert-org-file file)
    (let* ((tree (org-element-parse-buffer 'element))
           (excluded (blueprint--non-exported-subtrees tree))
           (dir (file-name-directory (expand-file-name file))))
      (delq nil
            (org-element-map tree 'keyword
              (lambda (kw)
                (when (and (string= (org-element-property :key kw) "INCLUDE")
                           (not (blueprint--in-regions-p
                                 (org-element-property :begin kw) excluded)))
                  (blueprint--parse-include-value
                   (org-element-property :value kw) dir))))))))

(defun blueprint--document-walk (&optional root)
  "Walk master.org of the project at ROOT and everything it includes.
Returns a plist:
  :files    master.org followed by every included file, depth first in
            document order, each file once; files included as a block
            are left out (their content is not live text);
  :missing  a list of (PATH . INCLUDING-FILE) for each include whose
            file does not exist;
  :partial  the files included only in part (\":lines\" or
            \"::search\"): they are counted whole.
Includes are followed recursively; a file already visited is not
walked again, so include cycles terminate.  Each file's include list
is cached (`blueprint--cached-metrics', kind `includes').  Returns
nil when master.org does not exist."
  (let ((master (blueprint--master-file root)))
    (when (file-exists-p master)
      (let ((files (list master))
            (missing '())
            (partial '()))
        (cl-labels
            ((walk (file)
               (dolist (inc (blueprint--cached-metrics
                             file #'blueprint--file-includes 'includes))
                 (let ((path (plist-get inc :path)))
                   (cond
                    ((plist-get inc :block))
                    ((not (file-exists-p path))
                     (push (cons path file) missing))
                    ((member path files))
                    (t
                     (when (plist-get inc :partial)
                       (push path partial))
                     (push path files)
                     (walk path)))))))
          (walk master))
        (list :files (nreverse files)
              :missing (nreverse missing)
              :partial (nreverse partial))))))

(defun blueprint--document-files (&optional root)
  "Return the files whose text makes up the document, in document order.
The document is the one of the project at ROOT, `blueprint--root' by
default: master.org and every file it includes with #+INCLUDE:,
recursively, resolving each path against the including file (see
`blueprint--document-walk').  Every count of the package (health
score, dashboard, pre-delivery check, lint, risks) reads only these
files, and in them only the exported text (see
`blueprint--uncounted-regions').

Limits: a file included in part (\":lines\", \"::search\") counts
whole; a file included twice counts once; each file's
#+EXCLUDE_TAGS: applies to that file only, while the exporter applies
the tags of master.org (and of every included file) to the whole
expanded document, and #+SELECT_TAGS: is not supported.  Without master.org the
document is not assembled yet, and the files are those that
`blueprint-sync' would include: the existing documents of every
component (`blueprint--component-document-paths'), components in
alphabetical order."
  (let ((walk (blueprint--document-walk root)))
    (if walk
        (plist-get walk :files)
      (let ((comps (let ((default-directory (or root default-directory)))
                     (blueprint--components))))
        (cl-loop for id in (sort (hash-table-keys comps) #'string<)
                 append (cl-loop for name in blueprint--component-document-files
                                 for path = (expand-file-name name (gethash id comps))
                                 when (file-exists-p path) collect path))))))

(defun blueprint--component-of-file (file comps)
  "Return the id of the component in COMPS whose directory holds FILE.
COMPS is a table as returned by `blueprint--components'.  Nil when
FILE lies outside every component directory."
  (catch 'found
    (maphash (lambda (id dir)
               (when (string-prefix-p (file-name-as-directory dir) file)
                 (throw 'found id)))
             comps)
    nil))

(defun blueprint--document-units ()
  "Return the rows the document is split into, for counts and navigation.
A list of plists with :id, :kind, :files and :included:
- one row of kind `component' per component, in alphabetical order:
  :files are its documents (`blueprint--component-document-paths')
  that are part of the document (`blueprint--document-files'),
  :included is nil when none is (component not synced into
  master.org);
- then one row of kind `part' per document file outside every
  component (master.org, glossary, Parte I and Parte V files,
  references...), in document order, with :id its path relative to
  the project root and :files the file alone.
Every document file belongs to exactly one row, so the rows add up
to the whole document."
  (let* ((root (blueprint--root))
         (comps (blueprint--components))
         (docs (blueprint--document-files))
         (units '()))
    (dolist (id (sort (hash-table-keys comps) #'string<))
      (let ((files (cl-remove-if-not (lambda (p) (member p docs))
                                     (blueprint--component-document-paths id))))
        (push (list :id id :kind 'component :files files :included (and files t))
              units)))
    (dolist (file docs)
      (unless (blueprint--component-of-file file comps)
        (push (list :id (file-relative-name file root) :kind 'part
                    :files (list file) :included t)
              units)))
    (nreverse units)))

(defun blueprint--document-part-file (id)
  "Return the absolute path of document part ID, or nil.
ID is a path relative to the project root as in the :id of a `part'
row of `blueprint--document-units'."
  (let ((path (expand-file-name id (blueprint--root))))
    (when (member path (blueprint--document-files)) path)))

(defun blueprint--component-included-paths (id)
  "Return the documents of component ID that are part of the document.
See `blueprint--document-units'."
  (let ((docs (blueprint--document-files)))
    (cl-remove-if-not (lambda (p) (member p docs))
                      (blueprint--component-document-paths id))))

;;; --- Component CRUD ---

;;; --- Component navigation ---

(defun blueprint--read-component-document (id &optional default label-fn)
  "Return the path of a document of component ID, asking which one.
The candidates are the existing files of
`blueprint--component-document-paths' (arc42.org, functional.org,
infrastructure.org).  With a single document no question is asked.
DEFAULT is the path or file name preselected, arc42.org when nil.
LABEL-FN, when non-nil, is called with each path and returns a
string shown after the file name (for example its marker counts).
Returns nil when ID is not a component."
  (let ((paths (blueprint--component-document-paths id)))
    (cond
     ((null paths) (blueprint--component-file id))
     ((null (cdr paths)) (car paths))
     (t
      (let* ((alist (mapcar
                     (lambda (path)
                       (cons (let ((name (file-name-nondirectory path)))
                               (if label-fn
                                   (format "%s %s" name (funcall label-fn path))
                                 name))
                             path))
                     paths))
             (default-name (file-name-nondirectory
                            (or default (car paths))))
             (default-label
              (car (cl-find-if
                    (lambda (cell)
                      (equal (file-name-nondirectory (cdr cell)) default-name))
                    alist)))
             (choice (completing-read
                      (format "Document of %s: " id)
                      (mapcar #'car alist) nil t nil nil
                      (or default-label (caar alist)))))
        (cdr (assoc choice alist)))))))

;;;###autoload
(defun blueprint-visit-component (id &optional document)
  "Visit a document of component ID, or the document part ID.
DOCUMENT is one of `blueprint--component-document-files'; when nil
and the component has more than one, ask which (arc42.org,
functional.org or infrastructure.org, existing files only).

ID may also name a part of the document outside the components, by
its path relative to the project root (\"master.org\",
\"nfr/risks.org\"...; see `blueprint--document-units'): the file is
visited directly.  Interactively both components and parts are
offered."
  (interactive
   (list (completing-read "Component or part: "
                          (mapcar (lambda (u) (plist-get u :id))
                                  (blueprint--document-units))
                          nil t)))
  (let* ((part (and (not (gethash id (blueprint--components)))
                    (blueprint--document-part-file id)))
         (file (cond
                (part)
                (document
                 (let ((dir (gethash id (blueprint--components))))
                   (when dir (expand-file-name document dir))))
                (t (blueprint--read-component-document id)))))
    (unless file (user-error "Component %s not found" id))
    (unless (file-exists-p file)
      (user-error "Component %s has no %s" id (file-name-nondirectory file)))
    (find-file file)))

(defun blueprint-components-visit ()
  "Visit a document of the component at point, asking which one."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id (blueprint-visit-component id))))

(defun blueprint-components-visit-arc42 ()
  "Visit arc42.org of the component at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id (blueprint-visit-component id "arc42.org"))))

(defun blueprint-components-visit-functional ()
  "Visit functional.org of the component at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id (blueprint-visit-component id "functional.org"))))

(defun blueprint-components-visit-infrastructure ()
  "Visit infrastructure.org of the component at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id (blueprint-visit-component id "infrastructure.org"))))

(defvar blueprint-components-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'blueprint-components-visit)
    (define-key map (kbd "a") #'blueprint-components-visit-arc42)
    (define-key map (kbd "f") #'blueprint-components-visit-functional)
    (define-key map (kbd "i") #'blueprint-components-visit-infrastructure)
    ;; `d' diff: defined in blueprint-diff.el, which requires this one;
    ;; the binding is installed by `blueprint-diff' at load time.
    map)
  "Keymap for `blueprint-components-mode'.")

(define-derived-mode blueprint-components-mode tabulated-list-mode
  "Blueprint Components"
  "Major mode for the list of Blueprint components.
\\<blueprint-components-mode-map>\\[blueprint-components-visit] asks which document of the component to open;
\\[blueprint-components-visit-arc42], \\[blueprint-components-visit-functional] and \\[blueprint-components-visit-infrastructure] open arc42.org,
functional.org and infrastructure.org directly."
  (setq tabulated-list-format [("Component" 30 t) ("Documents" 40 t)
                               ("Directory" 60 t)])
  (tabulated-list-init-header))

;;;###autoload
(defun blueprint-list-components ()
  "Display a list of all components in the current Blueprint project.
The Documents column lists the files of each component that reach
the document (see `blueprint-components-mode' for the keys that
open them)."
  (interactive)
  (let ((comps (blueprint--components))
        (entries '()))
    (maphash (lambda (id dir)
               (push (list id (vector
                               id
                               (mapconcat #'file-name-nondirectory
                                          (blueprint--component-document-paths id)
                                          " ")
                               (abbreviate-file-name dir)))
                     entries))
             comps)
    (if (null entries)
        (message "No components found.")
      (with-current-buffer (get-buffer-create "*Blueprint Components*")
        (blueprint-components-mode)
        (setq tabulated-list-entries
              (sort entries (lambda (a b) (string< (car a) (car b)))))
        (tabulated-list-print)
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

(defun blueprint--component-dependents (name &optional comps)
  "Return the sorted ids of the components that depend on NAME.
A component depends on NAME when its arc42.org declares NAME among the
tokens of #+BLUEPRINT_DEPENDS: (read with `blueprint--org-keyword')."
  (let ((comps (or comps (blueprint--components)))
        (result '()))
    (maphash
     (lambda (id dir)
       (unless (string= id name)
         (let ((deps (blueprint--org-keyword
                      (expand-file-name "arc42.org" dir)
                      "BLUEPRINT_DEPENDS")))
           (when (and deps (member name (split-string deps)))
             (push id result)))))
     comps)
    (sort result #'string<)))

(defun blueprint--remove-component-references (name)
  "Remove from master.org the synced references to component NAME.
Delegates to `blueprint--master-remove-component' (blueprint-sync),
required on demand so that the cleanup also works when only
blueprint-core is loaded.  Does nothing when blueprint-sync cannot be
loaded."
  (require 'blueprint-sync nil t)
  (when (fboundp 'blueprint--master-remove-component)
    (blueprint--master-remove-component name)))

;;;###autoload
(defun blueprint-delete-component (name)
  "Delete component NAME from the current Blueprint project.
Asks for confirmation, removes from master.org the synced #+INCLUDE:
lines and component headlines that reference NAME (see
`blueprint--master-remove-component') and reports the components that
still declare NAME in #+BLUEPRINT_DEPENDS:.  Those dependency lines
are left in place -- they need human judgement -- and the lint flags
them as dangling dependencies until they are resolved by hand."
  (interactive
   (let* ((comps (blueprint--components))
          (names (hash-table-keys comps)))
     (list (completing-read "Delete component: " names nil t))))
  (let* ((comps (blueprint--components))
         (dir (gethash name comps))
         (dependents (blueprint--component-dependents name comps)))
    (unless dir
      (user-error "Component %s not found" name))
    (when (if dependents
              (yes-or-no-p
               (format "%s still depends on %s in #+BLUEPRINT_DEPENDS: (the dependency will dangle, the lint flags it).  Really delete %s and all its files? "
                       (mapconcat #'identity dependents ", ") name name))
            (yes-or-no-p
             (format "Really delete component %s and all its files? " name)))
      (blueprint--remove-component-references name)
      (delete-directory dir t)
      (blueprint--invalidate-cache)
      (if dependents
          (message "Deleted component %s (dangling dependency in: %s)"
                   name (mapconcat #'identity dependents ", "))
        (message "Deleted component %s" name)))))

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

(defun blueprint--component-id (name)
  "Return the component id (directory name, diagram id) of NAME.
Lowercase, with every character other than a-z, 0-9 and \"-\" turned
into \"-\".  Until 2026-02 component directories were named as typed;
`blueprint-project-upgrade' renames them to this id."
  (replace-regexp-in-string "[^a-zA-Z0-9-]" "-" (downcase name)))

(defconst blueprint--component-templates
  '("component.org" "arc42-enterprise.org")
  "Templates `blueprint-add-component' can build arc42.org from.
\"component.org\" is the standard arc42 structure;
\"arc42-enterprise.org\" adds the enterprise sections (contesto
enterprise, stakeholder, compliance) for engagement-grade components.")

;;;###autoload
(defun blueprint-add-component (name &optional template-name)
  "Add a new component NAME to the current Blueprint project.
Creates the component directory under the data directory's
components/ (see `blueprint-directory-name') and
populates it from templates:
  - arc42.org         from TEMPLATE-NAME (default \"component.org\";
                      \"arc42-enterprise.org\" adds the enterprise
                      sections for engagement-grade components)
  - functional.org    from functional.org template (if available)
  - infrastructure.org from infrastructure.org template (if available)

Interactively, with \\[universal-argument] the arc42 template is
asked for among the templates of
`blueprint--component-templates' that resolve in the three-tier
lookup.  Template placeholders replaced:
  {{NAME}} -- component display name as entered
  {{ID}}   -- slugified name (lowercase, hyphens) for diagram IDs
  {{DATE}} -- current date (YYYY-MM-DD)"
  (interactive
   (list (read-string "Component name: ")
         (when current-prefix-arg
           (let ((candidates
                  (delq nil (mapcar (lambda (tmpl)
                                      (when (blueprint--resolve-template tmpl)
                                        tmpl))
                                    blueprint--component-templates))))
             (completing-read "arc42 template: "
                              (or candidates '("component.org"))
                              nil t nil nil (car candidates))))))
  (let* ((template-name (or template-name "component.org"))
         (id (blueprint--component-id name))
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
    ;; arc42.org -- always created, from the chosen template
    (let ((content (blueprint--template template-name)))
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
