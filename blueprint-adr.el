;;; blueprint-adr.el --- ADR management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Architecture Decision Record management: create, list, and navigate
;; ADRs stored in .blueprint/adr/.

;;; Code:

(require 'blueprint-core)

(defun blueprint--adr-dir ()
  "Return the ADR directory for the current Blueprint project."
  (expand-file-name ".blueprint/adr" (blueprint--root)))

(defun blueprint--adr-next-number ()
  "Return the next ADR number as a zero-padded string."
  (let* ((dir (blueprint--adr-dir))
         (files (and (file-directory-p dir)
                     (directory-files dir nil "^[0-9]\\{4\\}-.*\\.org$")))
         (max-num 0))
    (dolist (f files)
      (when (string-match "^\\([0-9]\\{4\\}\\)-" f)
        (let ((n (string-to-number (match-string 1 f))))
          (when (> n max-num) (setq max-num n)))))
    (format "%04d" (1+ max-num))))

;;;###autoload
(defun blueprint-adr-new (title)
  "Create a new Architecture Decision Record with TITLE."
  (interactive "sADR title: ")
  (let* ((dir (blueprint--adr-dir))
         (num (blueprint--adr-next-number))
         (slug (replace-regexp-in-string "[^a-zA-Z0-9]+" "-" (downcase title)))
         (filename (format "%s-%s.org" num slug))
         (file (expand-file-name filename dir))
         (content (blueprint--template "adr.org"))
         (date (format-time-string "%Y-%m-%d")))
    (make-directory dir t)
    (setq content (replace-regexp-in-string "{{NUMBER}}" num content t t))
    (setq content (replace-regexp-in-string "{{TITLE}}" title content t t))
    (setq content (replace-regexp-in-string "{{DATE}}" date content t t))
    (with-temp-file file
      (insert content))
    (find-file file)
    (message "Created ADR %s: %s" num title)))

;;;###autoload
(defun blueprint-adr-list ()
  "Display a list of all ADRs in the current Blueprint project."
  (interactive)
  (let* ((dir (blueprint--adr-dir))
         (files (and (file-directory-p dir)
                     (directory-files dir t "^[0-9]\\{4\\}-.*\\.org$")))
         (entries '()))
    (dolist (f files)
      (let* ((name (file-name-sans-extension (file-name-nondirectory f)))
             (status (or (with-temp-buffer
                           (insert-file-contents f)
                           (goto-char (point-min))
                           (when (re-search-forward "^#\\+STATUS:\\s-*\\(.*\\S-\\)" nil t)
                             (match-string 1)))
                         "unknown")))
        (push (list f (vector name status)) entries)))
    (if (null entries)
        (message "No ADRs found.")
      (with-current-buffer (get-buffer-create "*Blueprint ADRs*")
        (setq tabulated-list-format [("ADR" 50 t) ("Status" 20 t)]
              tabulated-list-entries (nreverse entries))
        (tabulated-list-mode)
        (tabulated-list-init-header)
        (tabulated-list-print)
        (local-set-key (kbd "RET")
                       (lambda ()
                         (interactive)
                         (let ((file (tabulated-list-get-id)))
                           (when file (find-file file)))))
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-adr)
;;; blueprint-adr.el ends here
