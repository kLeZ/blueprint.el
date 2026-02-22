;;; blueprint-roam.el --- Org-roam integration for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Optional integration with org-roam.  Registers component arc42.org
;; files as org-roam nodes, enabling backlink navigation between
;; components.  Requires org-roam to be installed.

;;; Code:

(require 'blueprint-core)

(defun blueprint--roam-available-p ()
  "Return non-nil if org-roam is available."
  (require 'org-roam nil t))

;;;###autoload
(defun blueprint-roam-setup ()
  "Configure org-roam to include Blueprint component directories.
Adds the .blueprint/components directory to `org-roam-directory' search."
  (interactive)
  (unless (blueprint--roam-available-p)
    (user-error "org-roam is not installed"))
  (let ((comp-dir (expand-file-name ".blueprint/components" (blueprint--root))))
    ;; Ensure components have org-roam IDs
    (maphash
     (lambda (_id dir)
       (let ((file (expand-file-name "arc42.org" dir)))
         (when (file-exists-p file)
           (with-current-buffer (find-file-noselect file)
             (goto-char (point-min))
             (unless (re-search-forward "^:ID:" nil t)
               (goto-char (point-min))
               (when (re-search-forward "^#\\+TITLE:" nil t)
                 (end-of-line)
                 (insert (format "\n:PROPERTIES:\n:ID: %s\n:END:"
                                 (org-id-new)))))
             (save-buffer)))))
     (blueprint--components))
    (message "Blueprint components configured for org-roam in %s" comp-dir)))

;;;###autoload
(defun blueprint-roam-find ()
  "Find a Blueprint component using org-roam's node finder."
  (interactive)
  (unless (blueprint--roam-available-p)
    (user-error "org-roam is not installed"))
  (let* ((comps (blueprint--components))
         (names (hash-table-keys comps))
         (name (completing-read "Blueprint component: " names nil t))
         (file (blueprint--component-file name)))
    (when file (find-file file))))

(provide 'blueprint-roam)
;;; blueprint-roam.el ends here
