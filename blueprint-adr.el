;;; blueprint-adr.el --- ADR management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Architecture Decision Record management for Blueprint.
;;
;; All ADRs live in a single consolidated file, adr.org in the project
;; data directory (`blueprint-directory-name', default `.blueprint/').
;; Each ADR is a level-1 heading with the form:
;;
;;   * ADR 0001: Title
;;   :PROPERTIES:
;;   :STATUS: proposed
;;   :DATE:   YYYY-MM-DD
;;   :END:
;;
;;   ** Contesto
;;   ** Decisione
;;   ** Conseguenze
;;
;; The STATUS property is stored in the standard Org PROPERTIES drawer so
;; it is both human-readable and accessible to `org-element', the column
;; view, and Org's property API -- without requiring a file-level keyword.
;;
;; Possible STATUS values: proposed, accepted, deprecated, superseded.
;;
;; Projects created before 2026-03 kept one file per ADR in the adr/
;; directory of the data directory (NNNN-slug.org with #+STATUS:).
;; They are read as they are (`blueprint--adr-entries'); moving them
;; into adr.org is an optional step of `blueprint-project-upgrade'.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

(defun blueprint--adr-file ()
  "Return the path to the consolidated ADR file (adr.org in the data directory)."
  (blueprint--data-path "adr.org"))

(defun blueprint--adr-legacy-dir ()
  "Return the directory of the ADRs written one per file.
Until 2026-03 (Blueprint 0.2.0) each ADR was a file
NNNN-slug.org in the adr/ directory of the data directory, with
#+TITLE: NNNN -- Title, #+DATE: and #+STATUS: keywords.  Those files
are still read (see `blueprint--adr-entries') and can be moved into
adr.org with `blueprint-project-upgrade'."
  (blueprint--data-path "adr"))

(defun blueprint--adr-legacy-files ()
  "Return the ADR files of the one-file-per-ADR model, sorted."
  (let ((dir (blueprint--adr-legacy-dir)))
    (and (file-directory-p dir)
         (sort (directory-files dir t "\\`[0-9]\\{4\\}-.*\\.org\\'")
               #'string<))))

(defun blueprint--adr-legacy-entry (file)
  "Return the ADR plist of the one-file ADR FILE.
The number comes from the file name, the title from #+TITLE: without
its \"NNNN -- \" prefix (any dash), status and date from #+STATUS: and
#+DATE:."
  (let* ((num (substring (file-name-nondirectory file) 0 4))
         (title (or (blueprint--org-keyword file "TITLE") ""))
         (title (if (string-match
                     "\\`[0-9]\\{4\\}[ \t]*[-\u2013\u2014:]+[ \t]*\\(.*\\)\\'" title)
                    (match-string 1 title)
                  title)))
    (list :number num
          :title title
          :status (downcase (or (blueprint--org-keyword file "STATUS")
                                "unknown"))
          :date (blueprint--org-keyword file "DATE")
          :file file
          :heading nil
          :legacy t)))

(defun blueprint--adr-entries ()
  "Return every ADR of the project, sorted by number.
A list of plists (:number :title :status :date :file :heading
:legacy): the level-1 headings `* ADR NNNN: Title' of adr.org (status
and date from the PROPERTIES drawer; headings the export leaves out,
like the template's :noexport: example ADR 0000, are skipped) and the
ADR files of the older one-file-per-ADR model (:legacy t), which are
read as they are, without asking for a migration."
  (let ((file (blueprint--adr-file))
        (entries '()))
    (when (file-exists-p file)
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (let* ((tree (org-element-parse-buffer 'headline))
               (exclude (blueprint--export-exclude-tags tree)))
          (org-element-map tree 'headline
            (lambda (hl)
              (let ((raw (or (org-element-property :raw-value hl) "")))
                (when (and (= (org-element-property :level hl) 1)
                           (not (blueprint--excluded-headline-p hl exclude))
                           (string-match
                            "\\`ADR \\([0-9]\\{4\\}\\):[ \t]*\\(.*\\)\\'" raw))
                  (push (list :number (match-string 1 raw)
                              :title (match-string 2 raw)
                              :status (downcase
                                       (or (org-element-property :STATUS hl)
                                           "unknown"))
                              :date (org-element-property :DATE hl)
                              :file file
                              :heading raw
                              :legacy nil)
                        entries))))))))
    (dolist (f (blueprint--adr-legacy-files))
      (push (blueprint--adr-legacy-entry f) entries))
    (sort entries (lambda (a b)
                    (string< (plist-get a :number) (plist-get b :number))))))

(defun blueprint--adr-next-number ()
  "Return the next ADR number as a zero-padded 4-digit string.
One past the highest number among the `* ADR NNNN:' headings of
adr.org (the template's example ADR 0000 included, so numbering
starts at 0001) and the ADR files of the one-file-per-ADR model.
Returns \"0001\" when there is no ADR."
  (let ((file (blueprint--adr-file))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^\\* ADR \\([0-9]\\{4\\}\\):" nil t)
          (let ((n (string-to-number (match-string 1))))
            (when (> n max-num) (setq max-num n))))))
    (dolist (f (blueprint--adr-legacy-files))
      (setq max-num (max max-num (string-to-number
                                  (substring (file-name-nondirectory f) 0 4)))))
    (format "%04d" (1+ max-num))))

(defun blueprint--adr-ensure-file ()
  "Create adr.org in the data directory from template if absent.
Return its path."
  (let ((file (blueprint--adr-file)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (let* ((content (blueprint--template "adr.org"))
             (project (file-name-nondirectory
                       (directory-file-name (blueprint--root))))
             (date (format-time-string "%Y-%m-%d")))
        (setq content (replace-regexp-in-string "{{PROJECT}}" project content t t))
        (setq content (replace-regexp-in-string "{{DATE}}" date content t t))
        (with-temp-file file (insert content))))
    file))

;;;###autoload
(defun blueprint-adr-new (title)
  "Add a new Architecture Decision Record with TITLE to adr.org.
The ADR is appended as a level-1 heading with STATUS=proposed in its
PROPERTIES drawer.  Creates adr.org from template if absent."
  (interactive "sADR title: ")
  (let* ((file (blueprint--adr-ensure-file))
         (num (blueprint--adr-next-number))
         (date (format-time-string "%Y-%m-%d"))
         (entry (blueprint--snippet "adr-entry"
                                `(("NUMBER" . ,num) ("TITLE" . ,title)
                                  ("DATE" . ,date)))))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (blueprint--insert-aligned entry)
      (save-buffer))
    (find-file file)
    (message "Added ADR %s: %s" num title)))

;;;###autoload
(defun blueprint-adr-list ()
  "Display a list of all ADRs of the project.
The ADRs of adr.org and those of the older one-file-per-ADR model
\(see `blueprint--adr-entries').  RET on an entry opens its file, at
the heading for an ADR of adr.org."
  (interactive)
  (let ((entries
         (mapcar (lambda (e)
                   (list (cons (plist-get e :file) (plist-get e :heading))
                         (vector (format "ADR %s: %s" (plist-get e :number)
                                         (plist-get e :title))
                                 (plist-get e :status)
                                 (if (plist-get e :legacy)
                                     (file-name-nondirectory (plist-get e :file))
                                   "adr.org"))))
                 (blueprint--adr-entries))))
    (if (null entries)
        (message "No ADRs found.")
      (with-current-buffer (get-buffer-create "*Blueprint ADRs*")
        (setq tabulated-list-format [("ADR" 50 t) ("Status" 12 t) ("File" 30 t)]
              tabulated-list-entries entries)
        (tabulated-list-mode)
        (tabulated-list-init-header)
        (tabulated-list-print)
        ;; A keymap of its own: `local-set-key' alone would bind RET
        ;; in the shared `tabulated-list-mode-map'.
        (use-local-map (make-composed-keymap nil tabulated-list-mode-map))
        (local-set-key (kbd "RET")
                       (lambda ()
                         (interactive)
                         (let ((data (tabulated-list-get-id)))
                           (when data
                             (find-file (car data))
                             (goto-char (point-min))
                             (when (and (cdr data)
                                        (search-forward (cdr data) nil t))
                               (beginning-of-line))))))
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-adr)
;;; blueprint-adr.el ends here
