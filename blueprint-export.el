;;; blueprint-export.el --- Org-native export for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; PDF, ODT, HTML, and DOCX export using the Org exporter.  DOCX export
;; requires ox-pandoc.  `blueprint-export-dispatch' hands off to Org's
;; own export menu (`org-export-dispatch') for any backend and any
;; per-file template/style choice Org already supports (e.g. an
;; #+ODT_STYLES_FILE: corporate template), instead of picking a backend
;; for the user.

;;; Code:

(require 'blueprint-core)
(require 'ox)
(require 'ox-odt)
(require 'ob-plantuml)

(declare-function org-pandoc-export-to-docx "ox-pandoc" (&optional async subtreep visible-only body-only ext-plist))

(defmacro blueprint--with-plantuml-export (&rest body)
  "Execute BODY with Babel/PlantUML configured for headless export.
A fresh or headless (`emacs -Q --batch') session has Babel evaluation
confirmation on and PlantUML in `jar' mode.  Without disabling the
former and switching the latter to the `plantuml' executable, every
`#+begin_src plantuml :file ...' block silently exports as a
source-code listing instead of the rendered diagram -- no error, no
warning (`org-odt-export-to-odt' and friends report success either
way).  An interactive session usually works by accident because the
user's own init.el already sets these.  Bindings here apply only for
the duration of BODY, and only for a variable still at its stock
default, so a user's own customization -- interactive or in a batch
wrapper -- is never overridden."
  (declare (indent 0) (debug t))
  `(let ((org-confirm-babel-evaluate
          (if (eq org-confirm-babel-evaluate t) nil org-confirm-babel-evaluate))
         (org-plantuml-exec-mode
          (if (eq org-plantuml-exec-mode 'jar) 'plantuml org-plantuml-exec-mode)))
     (org-babel-do-load-languages 'org-babel-load-languages '((plantuml . t)))
     ,@body))

(defcustom blueprint-export-backend 'pdf
  "Default export backend for Blueprint.
Supported values: pdf, odt, html, docx.  Override per-user (e.g. to
`odt' for a corporate ODT template via #+ODT_STYLES_FILE:) with
`:custom' in your own `use-package' block rather than changing this
default, which is shared by every Blueprint project/user."
  :type '(choice (const :tag "PDF (LaTeX)" pdf)
                 (const :tag "ODT (native Org)" odt)
                 (const :tag "HTML" html)
                 (const :tag "DOCX (Pandoc)" docx))
  :group 'blueprint)

(defun blueprint--strip-duplicate-titles (_backend)
  "Keep only the first #+TITLE keyword in the current export buffer.
Org expands #+INCLUDE verbatim, so every satellite file's own
#+TITLE (kept for standalone editing) survives into master.org's
export buffer.  Because #+TITLE has `parse' behaviour in
`org-export-options-alist', Org concatenates all of them into one
composite document title instead of keeping only the master's.

Uses `org-element' rather than a blind regex search so a #+TITLE:
line shown as sample text inside an example or source block (a
common pattern in tutorial-style Org files) is left untouched --
only real keyword nodes are removed.  Deletes from the last match
backward so earlier positions stay valid."
  (let (titles)
    (org-element-map (org-element-parse-buffer) 'keyword
      (lambda (kw)
        (when (equal (org-element-property :key kw) "TITLE")
          (push kw titles))))
    ;; TITLES is in reverse document order (last match first); keep
    ;; the true first occurrence (the last element) and delete the
    ;; rest, which are already ordered from last position to first.
    (dolist (kw (butlast titles))
      (delete-region (org-element-property :begin kw)
                      (org-element-property :end kw)))))

(add-hook 'org-export-before-parsing-functions #'blueprint--strip-duplicate-titles)

(defun blueprint--master-or-error ()
  "Return the master.org path, or signal an error if it does not exist.
Run `blueprint-init' or `blueprint-sync' to create master.org first."
  (let ((file (expand-file-name "master.org" (blueprint--root))))
    (unless (file-exists-p file)
      (user-error "No master.org found; run blueprint-init or blueprint-sync first"))
    file))

;;;###autoload
(defun blueprint-export-pdf ()
  "Export master.org to PDF via the Org LaTeX exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-latex-export-to-pdf))
      (message "Exported to PDF"))))

;;;###autoload
(defun blueprint-export-odt ()
  "Export master.org to ODT via the Org native ODT exporter.
Honours whatever #+ODT_STYLES_FILE: master.org declares (e.g. a
corporate template with letterhead), since this simply calls Org's
own `org-odt-export-to-odt' -- unlike PDF via LaTeX, no separate
template mechanism is involved."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-odt-export-to-odt))
      (message "Exported to ODT"))))

;;;###autoload
(defun blueprint-export-html ()
  "Export master.org to HTML via the Org HTML exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-html-export-to-html))
      (message "Exported to HTML"))))

;;;###autoload
(defun blueprint-export-docx ()
  "Export master.org to DOCX via ox-pandoc.
Requires the ox-pandoc package to be installed."
  (interactive)
  (unless (require 'ox-pandoc nil t)
    (user-error "Package ox-pandoc is required for DOCX export; install it first"))
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-pandoc-export-to-docx))
      (message "Exported to DOCX"))))

;;;###autoload
(defun blueprint-export ()
  "Export using the default backend (`blueprint-export-backend')."
  (interactive)
  (pcase blueprint-export-backend
    ('pdf (blueprint-export-pdf))
    ('odt (blueprint-export-odt))
    ('html (blueprint-export-html))
    ('docx (blueprint-export-docx))
    (_ (user-error "Unknown export backend: %s" blueprint-export-backend))))

;;;###autoload
(defun blueprint-export-dispatch ()
  "Open master.org and hand off to Org's own export menu.
Unlike `blueprint-export', which always uses
`blueprint-export-backend', this opens the standard
`org-export-dispatch' UI on master.org so any backend Org knows
about -- and any per-file choice Org already supports, such as an
alternate #+ODT_STYLES_FILE: or #+LATEX_CLASS: -- is picked
interactively instead of fixed in advance."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (call-interactively #'org-export-dispatch))))

(provide 'blueprint-export)
;;; blueprint-export.el ends here
