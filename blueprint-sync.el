;;; blueprint-sync.el --- Master file synchronization for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Synchronizes a master.org document with #+INCLUDE: directives for
;; every component.  Only the region between sync markers is updated;
;; manually written content is preserved.

;;; Code:

(require 'blueprint-core)

(defvar blueprint-sync-start-marker "# @@blueprint-sync-start@@"
  "Marker that begins the auto-generated component include section.")

(defvar blueprint-sync-end-marker "# @@blueprint-sync-end@@"
  "Marker that ends the auto-generated component include section.")

(defun blueprint--master-file ()
  "Return the path to the master.org file."
  (expand-file-name "master.org" (blueprint--root)))

(defun blueprint--ensure-master ()
  "Create master.org from template if it does not exist."
  (let ((file (blueprint--master-file)))
    (unless (file-exists-p file)
      (let* ((content (blueprint--template "master.org"))
             (project (file-name-nondirectory
                       (directory-file-name (blueprint--root))))
             (date (format-time-string "%Y-%m-%d")))
        (setq content (replace-regexp-in-string "{{PROJECT}}" project content t t))
        (setq content (replace-regexp-in-string "{{DATE}}" date content t t))
        (with-temp-file file
          (insert content))))
    file))

(defun blueprint--generate-includes ()
  "Generate #+INCLUDE: directives for all components, sorted by name."
  (let ((names (sort (hash-table-keys (blueprint--components)) #'string<))
        (lines '()))
    (dolist (name names)
      (push (format "#+INCLUDE: \".blueprint/components/%s/arc42.org\" :minlevel 2"
                    name)
            lines))
    (mapconcat #'identity (nreverse lines) "\n")))

;;;###autoload
(defun blueprint-sync ()
  "Synchronize the master.org file with current components.
Updates the region between sync markers with #+INCLUDE: directives.
Content outside the markers is preserved."
  (interactive)
  (let ((file (blueprint--ensure-master)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let ((start (search-forward blueprint-sync-start-marker nil t))
              (end (progn (goto-char (point-min))
                          (search-forward blueprint-sync-end-marker nil t))))
          (if (and start end)
              (progn
                (delete-region (1+ start) (line-beginning-position))
                (goto-char (1+ start))
                (insert "\n" (blueprint--generate-includes) "\n"))
            (goto-char (point-max))
            (insert "\n" blueprint-sync-start-marker "\n"
                    (blueprint--generate-includes) "\n"
                    blueprint-sync-end-marker "\n"))))
      (save-buffer))
    (message "Master file synchronized")))

(provide 'blueprint-sync)
;;; blueprint-sync.el ends here
