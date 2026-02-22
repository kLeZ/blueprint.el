;;; blueprint-migrate.el --- Template migration for Blueprint  -*- lexical-binding:t; -*-

(require 'blueprint-core)

;;;###autoload
(defun blueprint-template-diff ()
  "Compare project templates against system defaults.
Displays the diff in a `diff-mode' buffer."
  (interactive)
  (let ((default-directory (blueprint--root)))
    (compilation-start
     (format "diff -ru %s %s"
             (shell-quote-argument blueprint-template-dir)
             (shell-quote-argument (blueprint--project-template-dir)))
     'diff-mode)))

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
