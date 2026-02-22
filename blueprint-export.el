;;; blueprint-export.el --- Org-native export for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; PDF, HTML, and DOCX export using the Org exporter.  DOCX export
;; requires ox-pandoc.

;;; Code:

(require 'blueprint-core)
(require 'ox)

(declare-function org-pandoc-export-to-docx "ox-pandoc" (&optional async subtreep visible-only body-only ext-plist))

(defcustom blueprint-export-backend 'pdf
  "Default export backend for Blueprint.
Supported values: pdf, html, docx."
  :type '(choice (const :tag "PDF (LaTeX)" pdf)
                 (const :tag "HTML" html)
                 (const :tag "DOCX (Pandoc)" docx))
  :group 'blueprint)

(defun blueprint--master-or-error ()
  "Return the master.org path, creating it if needed."
  (let ((file (expand-file-name "master.org" (blueprint--root))))
    (unless (file-exists-p file)
      (user-error "No master.org found; run blueprint-sync first"))
    file))

;;;###autoload
(defun blueprint-export-pdf ()
  "Export master.org to PDF via the Org LaTeX exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (org-latex-export-to-pdf)
      (message "Exported to PDF"))))

;;;###autoload
(defun blueprint-export-html ()
  "Export master.org to HTML via the Org HTML exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (org-html-export-to-html)
      (message "Exported to HTML"))))

;;;###autoload
(defun blueprint-export-docx ()
  "Export master.org to DOCX via ox-pandoc.
Requires the ox-pandoc package to be installed."
  (interactive)
  (unless (require 'ox-pandoc nil t)
    (user-error "ox-pandoc is required for DOCX export; install it first"))
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (org-pandoc-export-to-docx)
      (message "Exported to DOCX"))))

;;;###autoload
(defun blueprint-export ()
  "Export using the default backend (`blueprint-export-backend')."
  (interactive)
  (pcase blueprint-export-backend
    ('pdf (blueprint-export-pdf))
    ('html (blueprint-export-html))
    ('docx (blueprint-export-docx))
    (_ (user-error "Unknown export backend: %s" blueprint-export-backend))))

(provide 'blueprint-export)
;;; blueprint-export.el ends here
