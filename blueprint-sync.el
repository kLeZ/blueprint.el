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
;;
;; Page breaks between components: when master.org declares
;;
;;   #+BLUEPRINT_PAGE_BREAK: components
;;
;; each synced section also gets a page break before every component
;; headline except the first, so that in the exported document each
;; component's section starts on a new page.  The break is written as
;; one keyword line per export backend (`#+ODT:' and `#+LATEX:'); each
;; backend emits its own line and ignores the other.  An Org macro
;; would be simpler to type but cannot work for ODT: it expands inside
;; a paragraph and would nest a <text:p> inside another.  The ODT line
;; references the paragraph style "PageBreak", which the
;; #+ODT_STYLES_FILE: must define (see `blueprint-check-odt-styles').

;;; Code:

(require 'blueprint-core)
(require 'blueprint-history)

;; The sync marker pairs (`blueprint-sync-start-marker' and friends)
;; live in blueprint-core.el: `blueprint-delete-component' removes the
;; synced references to a component from master.org, so both modules
;; need them and blueprint-core must not require blueprint-sync.

;;; --- Page breaks ---

(defconst blueprint-page-break-keyword "BLUEPRINT_PAGE_BREAK"
  "Org keyword in master.org that enables automatic page breaks.
The only supported value is \"components\": a page break before each
component headline of the synced sections except the first.")

(defconst blueprint--page-break-lines
  (concat "#+ODT: <text:p text:style-name=\"PageBreak\"/>\n"
          "#+LATEX: \\clearpage")
  "Org lines producing a page break in the ODT and LaTeX exports.
Each line is a backend-specific export keyword, so every backend emits
only its own and ignores the others.  The ODT line relies on a
paragraph style named \"PageBreak\" with fo:break-before=\"page\".")

(defun blueprint--page-break-mode ()
  "Return the page-break mode declared in the current buffer, or nil.
Reads `blueprint-page-break-keyword' (case-insensitive value).  Returns
the symbol `components' when the value is \"components\", nil when the
keyword is absent.  An unrecognized value is reported with a message
and treated as absent, so a typo never breaks the sync."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (when (re-search-forward
             (format "^#\\+%s:[ \t]*\\(.*?\\)[ \t]*$"
                     blueprint-page-break-keyword)
             nil t)
        (let ((value (downcase (match-string 1))))
          (if (string= value "components")
              'components
            (message "Unknown #+%s: value %S, ignored"
                     blueprint-page-break-keyword value)
            nil))))))

;;;###autoload
(defun blueprint-insert-page-break ()
  "Insert a page break at the beginning of the current line.
Writes `blueprint--page-break-lines', understood by the ODT and LaTeX
exporters.  Useful in any Org file of the project, outside the
sections managed by `blueprint-sync' (which inserts breaks between
components by itself when master.org declares
#+BLUEPRINT_PAGE_BREAK: components)."
  (interactive)
  (beginning-of-line)
  (insert blueprint--page-break-lines "\n"))

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

(defun blueprint--generate-includes-for (filename &optional page-breaks)
  "Generate #+INCLUDE: directives for FILENAME in component directories.
Only includes components that actually have FILENAME in their directory.
Components are sorted alphabetically by name.  Each include is preceded
by a level-2 headline naming the component (see
`blueprint--component-display-name'), so the assembled master.org marks
where one component's section ends and the next begins; the include
itself uses :minlevel 3 to nest under that headline.  When
PAGE-BREAKS is the symbol `components', `blueprint--page-break-lines'
precede every headline except the first.  Returns an empty string when
no matching files are found."
  (let ((root (blueprint--root))
        (names (sort (hash-table-keys (blueprint--components)) #'string<))
        (lines '()))
    (dolist (name names)
      (let ((dir (gethash name (blueprint--components))))
        (when (file-exists-p (expand-file-name filename dir))
          (push (concat
                 (when (and (eq page-breaks 'components) lines)
                   (concat blueprint--page-break-lines "\n"))
                 ;; Relative to master.org (at the project root), so the
                 ;; path follows `blueprint-directory-name'.
                 (format "** %s\n#+INCLUDE: \"%s\" :minlevel 3"
                         (blueprint--component-display-name name dir filename)
                         (file-relative-name (expand-file-name filename dir)
                                             root)))
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

(defun blueprint--sync-marker-regions ()
  "Return the (BEG . END) regions of the three sync-marker sections.
BEG is just after the start marker, END is the beginning of the end
marker line, so a region covers the synced content alone.  Sections
whose markers are missing are left out.  The search for each end
marker starts after its start marker, as `blueprint--sync-section'
does, so a stray end marker earlier in the buffer cannot interfere."
  (let ((regions '()))
    (dolist (pair (list (cons blueprint-sync-start-marker
                              blueprint-sync-end-marker)
                        (cons blueprint-sync-functional-start-marker
                              blueprint-sync-functional-end-marker)
                        (cons blueprint-sync-infra-start-marker
                              blueprint-sync-infra-end-marker)))
      (save-excursion
        (goto-char (point-min))
        (let ((start (search-forward (car pair) nil t)))
          (when start
            (let ((end (search-forward (cdr pair) nil t)))
              (when end
                (push (cons (1+ start)
                            (save-excursion (goto-char end)
                                            (line-beginning-position)))
                      regions)))))))
    (nreverse regions)))

(defun blueprint--master-remove-component (id)
  "Remove from master.org the synced references to component ID.
Inside each sync-marker section, deletes the #+INCLUDE: lines whose
target lives in the directory of ID, the level-2 headline
`blueprint--generate-includes-for' writes immediately before each of
them, and the page-break lines that precede that headline.  Content
outside the markers is never touched.  Does nothing when master.org
does not exist or no marker pair is present.

A page break left before the wrong component (because the first
remaining one should not have one) is cosmetic: the next
`blueprint-sync' regenerates the section exactly."
  (let* ((root (blueprint--root))
         (file (blueprint--master-file root))
         (dir (gethash id (blueprint--components))))
    (when (and dir (file-exists-p file))
      (with-current-buffer (find-file-noselect file)
        (let ((regions (blueprint--sync-marker-regions)))
          (when regions
            (let* ((mdir (file-name-directory file))
                   (breaks (split-string blueprint--page-break-lines "\n"))
                   (begins '()))
              (org-element-map (org-element-parse-buffer 'element) 'keyword
                (lambda (kw)
                  (when (and (string= (org-element-property :key kw) "INCLUDE")
                             (blueprint--in-regions-p
                              (org-element-property :begin kw) regions))
                    (let ((inc (blueprint--parse-include-value
                                (org-element-property :value kw) mdir)))
                      (when (and inc
                                 (string-prefix-p (file-name-as-directory dir)
                                                  (plist-get inc :path)))
                        (push (org-element-property :begin kw) begins))))))
              (dolist (beg (sort begins #'>))
                (save-excursion
                  (goto-char beg)
                  (beginning-of-line)
                  ;; The #+INCLUDE: line itself.
                  (delete-region (point) (line-beginning-position 2))
                  ;; The generated headline sits on the line right above
                  ;; the include; the page-break lines, when enabled,
                  ;; right above the headline.
                  (forward-line -1)
                  (when (looking-at "^\\*\\* ")
                    (delete-region (point) (line-beginning-position 2))
                    (forward-line -1)
                    (while (and (not (bobp))
                                (member (buffer-substring
                                         (line-beginning-position)
                                         (line-end-position))
                                        breaks))
                      (delete-region (point) (line-beginning-position 2))
                      (forward-line -1))))))
            (save-buffer)))))))

;;;###autoload
(defun blueprint-sync ()
  "Synchronize the master.org file with current components.
Updates the three auto-managed sections (arc42, functional, infra)
between their respective sync markers.  Content outside all markers
is preserved.  Creates master.org from template if absent.  When
master.org declares #+BLUEPRINT_PAGE_BREAK: components, each section
gets a page break between consecutive components (see
`blueprint--page-break-mode')."
  (interactive)
  (let ((file (blueprint--ensure-master)))
    (with-current-buffer (find-file-noselect file)
      (let ((breaks (blueprint--page-break-mode)))
        (blueprint--sync-section
         blueprint-sync-start-marker
         blueprint-sync-end-marker
         (blueprint--generate-includes-for "arc42.org" breaks))
        (blueprint--sync-section
         blueprint-sync-functional-start-marker
         blueprint-sync-functional-end-marker
         (blueprint--generate-includes-for "functional.org" breaks))
        (blueprint--sync-section
         blueprint-sync-infra-start-marker
         blueprint-sync-infra-end-marker
         (blueprint--generate-includes-for "infrastructure.org" breaks)))
      (save-buffer))
    ;; Metrics history: non-fatal, so a problem there never breaks the
    ;; sync.
    (when blueprint-history-on-sync
      (condition-case err
          (blueprint-history-record)
        (error (message "Blueprint history: %s" (error-message-string err)))))
    (message "Master file synchronized")))

(provide 'blueprint-sync)
;;; blueprint-sync.el ends here
