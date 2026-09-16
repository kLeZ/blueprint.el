;;; blueprint-sync.el --- Master file synchronization for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Synchronizes a master.org document with #+INCLUDE: directives for
;; every component.  Only the regions between sync markers are updated;
;; manually written content is preserved.
;;
;; Three sections of master.org are managed automatically:
;;
;;   Parte II (architettura per componente) -- arc42.org files
;;     delimited by: @@blueprint-sync-start@@ / @@blueprint-sync-end@@
;;
;;   Parte III (specifiche funzionali) -- functional.org files
;;     delimited by: @@blueprint-sync-functional-start@@ / @@blueprint-sync-functional-end@@
;;
;;   Parte IV (censimento infrastrutturale) -- infrastructure.org files
;;     delimited by: @@blueprint-sync-infra-start@@ / @@blueprint-sync-infra-end@@
;;
;; If a pair of markers is absent from master.org the corresponding
;; section is left untouched (backward compatible with projects that
;; use only the original arc42 markers).

;;; Code:

(require 'blueprint-core)

(defvar blueprint-sync-start-marker "# @@blueprint-sync-start@@"
  "Marker that begins the auto-generated arc42 include section.")

(defvar blueprint-sync-end-marker "# @@blueprint-sync-end@@"
  "Marker that ends the auto-generated arc42 include section.")

(defvar blueprint-sync-functional-start-marker
  "# @@blueprint-sync-functional-start@@"
  "Marker that begins the auto-generated functional spec include section.")

(defvar blueprint-sync-functional-end-marker
  "# @@blueprint-sync-functional-end@@"
  "Marker that ends the auto-generated functional spec include section.")

(defvar blueprint-sync-infra-start-marker
  "# @@blueprint-sync-infra-start@@"
  "Marker that begins the auto-generated infrastructure include section.")

(defvar blueprint-sync-infra-end-marker
  "# @@blueprint-sync-infra-end@@"
  "Marker that ends the auto-generated infrastructure include section.")

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
        (setq content (replace-regexp-in-string "{{AUTHOR}}" (user-full-name) content t t))
        (setq content (replace-regexp-in-string "{{DATE}}" date content t t))
        (with-temp-file file
          (insert content))))
    file))

(defun blueprint--generate-includes ()
  "Generate #+INCLUDE: directives for arc42.org in all components, sorted by name."
  (blueprint--generate-includes-for "arc42.org"))

(defun blueprint--component-display-name (name dir filename)
  "Return a human-readable display name for component NAME.
Reads the #+TITLE: keyword from FILENAME inside DIR, if present, and
returns the text before the first \" -- \" separator (the convention
used by Blueprint's own component templates, e.g. \"Portale --
Architettura (arc42)\").  Falls back to the unparsed title, and to NAME
capitalized, if FILENAME is unreadable or has no #+TITLE: line."
  (let ((file (expand-file-name filename dir)))
    (or (when (file-exists-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
              (let ((title (string-trim (match-string 1))))
                (cond
                 ((string-empty-p title) nil)
                 ((string-match "\\`\\(.*?\\)[ \t]+--[ \t]+" title)
                  (match-string 1 title))
                 (t title))))))
        (capitalize name))))

(defun blueprint--generate-includes-for (filename)
  "Generate #+INCLUDE: directives for FILENAME in component directories.
Only includes components that actually have FILENAME in their directory.
Components are sorted alphabetically by name.  Each include is preceded
by a level-2 headline naming the component (see
`blueprint--component-display-name'), so the assembled master.org marks
where one component's section ends and the next begins; the include
itself uses :minlevel 3 to nest under that headline.  Returns an empty
string when no matching files are found."
  (let ((names (sort (hash-table-keys (blueprint--components)) #'string<))
        (lines '()))
    (dolist (name names)
      (let ((dir (gethash name (blueprint--components))))
        (when (file-exists-p (expand-file-name filename dir))
          (push (format "** %s\n#+INCLUDE: \".blueprint/components/%s/%s\" :minlevel 3"
                        (blueprint--component-display-name name dir filename)
                        name filename)
                lines))))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun blueprint--sync-section (start-marker end-marker content)
  "Replace the text between START-MARKER and END-MARKER with CONTENT.
Both markers must be present in the current buffer; if either is absent
the function does nothing (safe to call on older master.org files).

The search for END-MARKER starts from the position immediately after
START-MARKER, so duplicate or misplaced markers earlier in the buffer
cannot interfere."
  (save-excursion
    (goto-char (point-min))
    (let ((start (search-forward start-marker nil t)))
      (when start
        ;; Search for end-marker from AFTER start-marker, not from
        ;; point-min.  Searching from the beginning would match a stray
        ;; end-marker appearing before start-marker, causing delete-region
        ;; to receive inverted arguments and signal an error.
        (let ((end (search-forward end-marker nil t)))
          (when end
            (delete-region (1+ start) (line-beginning-position))
            (goto-char (1+ start))
            ;; (1+ start) already sits at the beginning of the line right
            ;; after start-marker, so no extra leading newline is needed
            ;; before CONTENT (it used to produce a spurious blank line
            ;; between the marker and the synced content on every sync).
            (unless (string= "" content)
              (insert content "\n"))))))))

;;;###autoload
(defun blueprint-sync ()
  "Synchronize the master.org file with current components.
Updates the three auto-managed sections (arc42, functional, infra)
between their respective sync markers.  Content outside all markers
is preserved.  Creates master.org from template if absent."
  (interactive)
  (let ((file (blueprint--ensure-master)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--sync-section
       blueprint-sync-start-marker
       blueprint-sync-end-marker
       (blueprint--generate-includes-for "arc42.org"))
      (blueprint--sync-section
       blueprint-sync-functional-start-marker
       blueprint-sync-functional-end-marker
       (blueprint--generate-includes-for "functional.org"))
      (blueprint--sync-section
       blueprint-sync-infra-start-marker
       blueprint-sync-infra-end-marker
       (blueprint--generate-includes-for "infrastructure.org"))
      (save-buffer))
    (message "Master file synchronized")))

(provide 'blueprint-sync)
;;; blueprint-sync.el ends here
