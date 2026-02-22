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
