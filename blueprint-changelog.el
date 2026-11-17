;;; blueprint-changelog.el --- Changelog generation for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
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
(require 'blueprint-adr)
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
The ADRs of `blueprint--adr-entries' with status accepted: the
level-1 headings `* ADR NNNN: Title' of .blueprint/adr.org with
:STATUS: accepted (headings the export leaves out, like the example
\"ADR 0000\" of the adr.org template, are not ADRs of the project) and
the accepted ADR files of the older one-file-per-ADR model.  nil
without accepted ADRs."
  (delq nil
        (mapcar (lambda (e)
                  (when (string= (plist-get e :status) "accepted")
                    (list (plist-get e :number)
                          (plist-get e :title)
                          (plist-get e :date))))
                (blueprint--adr-entries))))

(defun blueprint--changelog-assembly (log-entries adrs project)
  "Return the contents of CHANGELOG.org.
LOG-ENTRIES is a list of (HASH DATE SUBJECT) as
`blueprint--changelog-parse-log' returns, ADRS one of
\(NUMBER TITLE DATE) as `blueprint--changelog-adr-accepted', PROJECT
the display name of the project."
  (concat
   (format "#+TITLE: CHANGELOG — %s\n\n" project)
   (blueprint--l10n 'changelog-intro) "\n\n"
   (format "* %s\n\n" (blueprint--l10n 'changelog-history))
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
         (setq out (concat (blueprint--l10n 'changelog-no-commits) "\n")))
       out))
   (format "* %s\n\n" (blueprint--l10n 'changelog-adrs))
   (if adrs
       (mapconcat (lambda (a)
                    (format "- ADR %s (%s): %s\n" (car a) (nth 2 a) (nth 1 a)))
                  adrs "")
     (concat (blueprint--l10n 'changelog-no-adrs) "\n"))))

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
