
;;; blueprint-migrate.el
(require 'blueprint-core)

(defun blueprint-template-diff ()
  "Diff project templates vs defaults."
  (interactive)
  (let ((default-directory (blueprint--root)))
    (compilation-start
     (format "diff -ru %s %s"
             blueprint-template-dir
             (blueprint--project-template-dir))
     'diff-mode)))

(defun blueprint-template-migrate ()
  "Interactive merge helper (copy missing files only)."
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
