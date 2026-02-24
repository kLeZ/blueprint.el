;;; blueprint-migrate.el --- Template migration for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Compares project templates against system defaults (diff) and copies
;; missing template files into the project (non-destructive migration).

;;; Code:

(require 'blueprint-core)

;;;###autoload
(defun blueprint-template-diff ()
  "Compare project templates against system defaults.
Displays the diff in a `diff-mode' buffer.
Signals an error if the project templates directory does not exist."
  (interactive)
  (let ((proj-dir (blueprint--project-template-dir)))
    (unless (file-directory-p proj-dir)
      (user-error "No project templates directory; run blueprint-template-migrate first"))
    (let ((default-directory (blueprint--root)))
      (compilation-start
       (format "diff -ru %s %s"
               (shell-quote-argument blueprint-template-dir)
               (shell-quote-argument proj-dir))
       'diff-mode))))

;;;###autoload
(defun blueprint-template-migrate ()
  "Copy missing template files from system defaults to the project.
Only adds files that do not already exist in the project templates
directory (non-destructive)."
  (interactive)
  (let ((src blueprint-template-dir)
        (dst (blueprint--project-template-dir)))
    (make-directory dst t)
    (dolist (f (directory-files src t "^[^.]"))
      (let ((target (expand-file-name (file-name-nondirectory f) dst)))
        (unless (file-exists-p target)
          (copy-file f target))))
    (message "Templates migrated (non-destructive)")))

(provide 'blueprint-migrate)
;;; blueprint-migrate.el ends here
