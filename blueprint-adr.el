;;; blueprint-adr.el --- ADR management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
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

;;; Code:

(require 'blueprint-core)
(require 'org-element)

(defun blueprint--adr-file ()
  "Return the path to the consolidated ADR file (adr.org in the data directory)."
  (blueprint--data-path "adr.org"))

(defun blueprint--adr-next-number ()
  "Return the next ADR number as a zero-padded 4-digit string.
Scans level-1 headings matching `* ADR NNNN:' in adr.org and increments
past the highest number found.  Returns \"0001\" when the file is absent
or contains no ADR headings."
  (let ((file (blueprint--adr-file))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^\\* ADR \\([0-9]\\{4\\}\\):" nil t)
          (let ((n (string-to-number (match-string 1))))
            (when (> n max-num) (setq max-num n))))))
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
         (entry (concat
                 (format "* ADR %s: %s\n" num title)
                 ":PROPERTIES:\n"
                 ":STATUS: proposed\n"
                 (format ":DATE:   %s\n" date)
                 ":END:\n\n"
                 "** Contesto\n\n"
                 "Situazione e forze in gioco che hanno motivato questa decisione.\n\n"
                 "** Decisione\n\n"
                 "La decisione presa e le alternative considerate.\n\n"
                 "** Conseguenze\n\n"
                 "Conseguenze positive, negative e neutre di questa decisione.\n\n")))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert entry)
      (save-buffer))
    (find-file file)
    (message "Added ADR %s: %s" num title)))

;;;###autoload
(defun blueprint-adr-list ()
  "Display a list of all ADRs from the consolidated adr.org.
RET on an entry opens adr.org and jumps to the corresponding heading."
  (interactive)
  (let* ((file (blueprint--adr-file))
         (entries '()))
    (when (file-exists-p file)
      (with-temp-buffer
        (blueprint--insert-org-file file)
        ;; Headings the export leaves out (the template's :noexport:
        ;; example "ADR 0000", COMMENTed drafts) are not decisions of
        ;; the project.
        (let* ((tree (org-element-parse-buffer 'headline))
               (exclude (blueprint--export-exclude-tags tree)))
          (org-element-map tree 'headline
            (lambda (hl)
              (when (and (= (org-element-property :level hl) 1)
                         (not (blueprint--excluded-headline-p hl exclude))
                         (string-match-p "^ADR [0-9]\\{4\\}:"
                                         (or (org-element-property :raw-value hl) "")))
                (let* ((raw (org-element-property :raw-value hl))
                       (status (or (org-element-property :STATUS hl) "unknown")))
                  (push (list (cons file raw) (vector raw status)) entries))))))))
    (if (null entries)
        (message "No ADRs found.")
      (with-current-buffer (get-buffer-create "*Blueprint ADRs*")
        (setq tabulated-list-format [("ADR" 50 t) ("Status" 20 t)]
              tabulated-list-entries (nreverse entries))
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
                             (when (search-forward (cdr data) nil t)
                               (beginning-of-line))))))
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-adr)
;;; blueprint-adr.el ends here
