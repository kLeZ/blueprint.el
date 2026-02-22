
;;; blueprint-core.el -*- lexical-binding:t; -*-
(require 'cl-lib)
(require 'org)

(defgroup blueprint nil "" :group 'tools)

(defcustom blueprint-template-dir
  (expand-file-name "templates" (file-name-directory load-file-name)) "")

(defcustom blueprint-user-template-dir
  (expand-file-name "~/.config/blueprint/templates") "")

(defun blueprint--root ()
  (or (locate-dominating-file default-directory ".blueprint")
      (user-error "Not in blueprint project")))

(defun blueprint-init ()
  (interactive)
  (let ((r (expand-file-name ".blueprint" default-directory)))
    (make-directory r t)
    (make-directory (expand-file-name "components" r) t)
    (make-directory (expand-file-name "adr" r) t)
    (message "Blueprint initialized")))

(defun blueprint--components ()
  (let* ((dir (expand-file-name ".blueprint/components" (blueprint--root)))
         (tbl (make-hash-table :test 'equal)))
    (when (file-exists-p dir)
      (dolist (d (directory-files dir t "^[^.]"))
        (when (file-directory-p d)
          (puthash (file-name-nondirectory d) d tbl))))
    tbl)

(defun blueprint--component-file (id)
  (expand-file-name "arc42.org" (gethash id (blueprint--components))))

(defun blueprint--project-template-dir ()
  (expand-file-name ".blueprint/templates" (blueprint--root)))

(defun blueprint--resolve-template (name)
  (cl-loop for d in (list (blueprint--project-template-dir)
                          blueprint-user-template-dir
                          blueprint-template-dir)
           for p = (expand-file-name name d)
           when (file-exists-p p) return p))

(defun blueprint--template (name)
  (with-temp-buffer
    (insert-file-contents (blueprint--resolve-template name))
    (buffer-string)))

(defun blueprint-add-component (name)
  (interactive "sComponent: ")
  (let* ((dir (expand-file-name name
                                (expand-file-name ".blueprint/components"
                                                  (blueprint--root))))
         (file (expand-file-name "arc42.org" dir)))
    (make-directory dir t)
    (with-temp-file file
      (insert (blueprint--template "component.org")))
    (find-file file))

(provide 'blueprint-core)
