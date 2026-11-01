;;; blueprint-changelog.el --- Changelog generation for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Generates CHANGELOG.org at the project root from two sources:
;;
;; - the messages of the git commits (`git log', most recent first,
;;   grouped by date; with SINCE, only SINCE..HEAD);
;; - the accepted ADRs of .blueprint/adr.org (the ones with
;;   :STATUS: accepted in their PROPERTIES drawer).
;;
;; The file is derived: every run regenerates it completely, and when
;; one already exists the command asks before overwriting manual edits.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

(defun blueprint--changelog-git-log (&optional since)
  "Return the parsed `git log' entries of the project.
SINCE, when non-nil, restricts the log to SINCE..HEAD.  Each entry is
a (HASH DATE SUBJECT) list, most recent first.  Signals `user-error'
when git is not available or the project is not a git repository."
  (let* ((root (blueprint--root))
         (default-directory root)
         (args (if since
                   (list "log" "--date=short" "--pretty=%h|%ad|%s"
                         (concat since "..HEAD"))
                 (list "log" "--date=short" "--pretty=%h|%ad|%s"))))
    (with-temp-buffer
      (let ((exit (condition-case err
                      (apply #'call-process "git" nil t nil args)
                    (file-missing
                     (user-error "git not found: %s" (error-message-string err))))))
        (unless (zerop exit)
          (user-error "git log failed (exit %d): is %s a git repository?" exit root))
        (blueprint--changelog-parse-log (buffer-string))))))

(defun blueprint--changelog-parse-log (output)
  "Parse the git log OUTPUT lines of the form `%h|%ad|%s'.
Returns a list of (HASH DATE SUBJECT), most recent first."
  (let ((entries '()))
    (dolist (line (split-string output "\n" t))
      (when (string-match "\\`\\([0-9a-f]+\\)|\\([0-9-]+\\)|\\(.*\\)\\'" line)
        (push (list (match-string 1 line)
                    (match-string 2 line)
                    (match-string 3 line))
              entries)))
    (nreverse entries)))

(defun blueprint--changelog-adr-accepted ()
  "Return the accepted ADRs of the project as (NUMBER TITLE DATE) lists.
The ADRs are the level-1 headings `* ADR NNNN: Title' of
.blueprint/adr.org with :STATUS: accepted in their PROPERTIES drawer;
DATE is the :DATE: property.  Headings the export leaves out
\(:noexport: or COMMENT) are skipped: the example \"ADR 0000\" of the
adr.org template is one of them and is not a decision of the project.
nil without adr.org or without accepted ADRs."
  (let ((file (blueprint--data-path "adr.org"))
        (adrs '()))
    (when (file-exists-p file)
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (let* ((tree (org-element-parse-buffer 'headline))
               (exclude (blueprint--export-exclude-tags tree)))
          (org-element-map tree 'headline
            (lambda (hl)
              (when (and (= (org-element-property :level hl) 1)
                         (not (blueprint--excluded-headline-p hl exclude))
                         (string= (downcase
                                   (or (org-element-property :STATUS hl) ""))
                                  "accepted"))
                (let ((raw (org-element-property :raw-value hl))
                      (date (org-element-property :DATE hl)))
                  (when (and raw
                             (string-match
                              "\\`ADR \\([0-9]\\{4\\}\\):[ \t]*\\(.*\\)\\'" raw))
                    (push (list (match-string 1 raw)
                                (match-string 2 raw)
                                date)
                          adrs))))))))
      (nreverse adrs))))

(defun blueprint--changelog-assembly (log-entries adrs project)
  "Return the contents of CHANGELOG.org.
LOG-ENTRIES is a list of (HASH DATE SUBJECT) as
`blueprint--changelog-parse-log' returns, ADRS one of
\(NUMBER TITLE DATE) as `blueprint--changelog-adr-accepted', PROJECT
the display name of the project."
  (concat
   (format "#+TITLE: CHANGELOG — %s\n\n" project)
   "File generato da `blueprint-changelog-generate': messaggi dei\n"
   "commit git (più recenti prima, raggruppati per data) e ADR\n"
   "accettate.  Le modifiche manuali andranno perse alla prossima\n"
   "rigenerazione.\n\n"
   "* Cronologia\n\n"
   (progn
     (let ((out "")
           (current-date nil)
           (first t))
       (dolist (entry log-entries)
         (let ((date (nth 1 entry)))
           (unless (equal date current-date)
             (unless first (setq out (concat out "\n")))
             (setq first nil)
             (setq out (concat out (format "** %s\n\n" date)))
             (setq current-date date)))
         (setq out (concat out (format "- %s %s\n"
                                       (car entry) (nth 2 entry)))))
       (when log-entries (setq out (concat out "\n")))
       (when (string-empty-p out)
         (setq out "Nessun commit registrato.\n"))
       out))
   "* Decisioni architetturali (ADR accettate)\n\n"
   (if adrs
       (mapconcat (lambda (a)
                    (format "- ADR %s (%s): %s\n" (car a) (nth 2 a) (nth 1 a)))
                  adrs "")
     "Nessuna ADR accettata.\n")))

;;;###autoload
(defun blueprint-changelog-generate (&optional since)
  "Generate CHANGELOG.org from the git history and the accepted ADRs.
SINCE, when non-nil (or when asked interactively and given), restricts
the cronology to SINCE..HEAD (a tag or a commit).  The file is fully
regenerated; when one already exists, the command asks before
overwriting manual edits.  Returns the file path."
  (interactive
   (list (when current-prefix-arg
           (let ((s (read-string "Since (tag/commit, empty for all): ")))
             (and (not (string-empty-p s)) s)))))
  (let* ((root (blueprint--root))
         (file (expand-file-name "CHANGELOG.org" root))
         (project (file-name-nondirectory (directory-file-name root))))
    (when (and (file-exists-p file)
               (not (yes-or-no-p
                     "CHANGELOG.org already exists: regenerate it from git and the ADRs? Manual edits will be lost. ")))
      (user-error "Cancelled"))
    (with-temp-file file
      (insert (blueprint--changelog-assembly
               (blueprint--changelog-git-log since)
               (blueprint--changelog-adr-accepted)
               project)))
    (message "Changelog written to %s" file)
    file))

(provide 'blueprint-changelog)
;;; blueprint-changelog.el ends here
