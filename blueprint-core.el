;;; blueprint-core.el --- Core utilities for Blueprint  -*- lexical-binding:t; -*-

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

;;;###autoload
(defun blueprint-init ()
  "Initialize a new Blueprint project in the current directory.
Creates the .blueprint directory with components and adr subdirectories."
  (interactive)
  (let ((r (expand-file-name ".blueprint" default-directory)))
    (make-directory r t)
    (make-directory (expand-file-name "components" r) t)
    (make-directory (expand-file-name "adr" r) t)
    (message "Blueprint initialized in %s" default-directory)))

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
                   (let ((line (match-string 0)))
                     (when (string-match (format "\\b%s\\b" (regexp-quote old-name)) line)
                       (setq modified t)
                       (replace-match
                        (replace-regexp-in-string
                         (format "\\b%s\\b" (regexp-quote old-name))
                         new-name line t t)))))
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
Creates the component directory and populates it from the component template.
Template placeholders ({{NAME}}) are replaced with the component name."
  (interactive "sComponent: ")
  (let* ((dir (expand-file-name name
                                (expand-file-name ".blueprint/components"
                                                  (blueprint--root))))
         (file (expand-file-name "arc42.org" dir))
         (content (replace-regexp-in-string
                   "{{NAME}}" name
                   (blueprint--template "component.org") t t)))
    (make-directory dir t)
    (with-temp-file file
      (insert content))
    (find-file file)))

(provide 'blueprint-core)
;;; blueprint-core.el ends here
