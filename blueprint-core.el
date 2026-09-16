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

(defun blueprint--root ()
  "Return the root directory of the current Blueprint project.
Signals an error if not inside a Blueprint project."
  (or (locate-dominating-file default-directory ".blueprint")
      (user-error "Not in a Blueprint project (no .blueprint directory found)")))

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

Creates the following structure:

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
         (bp (expand-file-name ".blueprint" root))
         (pname (or project-name
                    (file-name-nondirectory (directory-file-name root))))
         (pauthor (or author (user-full-name)))
         (date (format-time-string "%Y-%m-%d"))
         (replacements `(("{{PROJECT}}" . ,pname)
                         ("{{AUTHOR}}"  . ,pauthor)
                         ("{{DATE}}"    . ,date))))
    ;; 1. .blueprint/ internals
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
  (let* ((dir (expand-file-name ".blueprint/components" (blueprint--root)))
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
      (remhash file blueprint--metrics-cache)
    (clrhash blueprint--metrics-cache)))

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
             (with-temp-buffer
               (insert-file-contents file)
               (goto-char (point-min))
               (let ((modified nil))
                 (while (re-search-forward "^#\\+BLUEPRINT_DEPENDS:.*" nil t)
                   (let* ((line (match-string 0))
                          (new-line (replace-regexp-in-string
                                     (format "\\b%s\\b" (regexp-quote old-name))
                                     new-name line t t)))
                     (unless (string= line new-line)
                       (setq modified t)
                       (replace-match new-line t t))))
                 (when modified
                   (write-region (point-min) (point-max) file)))))))
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
  (expand-file-name ".blueprint/templates" (blueprint--root)))

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
Creates the component directory under .blueprint/components/ and
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
                                (expand-file-name ".blueprint/components"
                                                  (blueprint--root))))
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
