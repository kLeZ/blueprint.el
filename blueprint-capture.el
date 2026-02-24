;;; blueprint-capture.el --- Quick capture for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Configures org-capture templates for quick note-taking in Blueprint
;; projects: notes, questions, and glossary terms.

;;; Code:

(require 'blueprint-core)
(require 'org-capture)

(defun blueprint--notes-file ()
  "Return the path to the project notes file."
  (let ((file (expand-file-name ".blueprint/notes.org" (blueprint--root))))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "#+TITLE: Project Notes\n\n")))
    file))

(defun blueprint--capture-templates ()
  "Return Blueprint-specific org-capture templates."
  (let ((root (ignore-errors (blueprint--root))))
    (when root
      `(("bn" "Blueprint note" entry
         (file ,(blueprint--notes-file))
         "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n")
        ("bq" "Blueprint question" entry
         (file ,(blueprint--notes-file))
         "* QUESTION %?\n:PROPERTIES:\n:COMPONENT: \n:CREATED: %U\n:END:\n")
        ("bg" "Blueprint glossary term" entry
         (file ,(expand-file-name ".blueprint/glossary.org" root))
         "* %^{Term}\n:PROPERTIES:\n:SOURCE: %^{Source}\n:END:\n%?")))))

;;;###autoload
(defun blueprint-capture-setup ()
  "Register Blueprint capture templates with `org-capture'.
Safe to call multiple times; existing templates are preserved."
  (interactive)
  (let ((templates (blueprint--capture-templates)))
    (dolist (tmpl templates)
      (unless (assoc (car tmpl) org-capture-templates)
        (push tmpl org-capture-templates)))
    (message "Blueprint capture templates registered")))

;;;###autoload
(defun blueprint-capture ()
  "Launch `org-capture' with Blueprint templates pre-loaded."
  (interactive)
  (blueprint-capture-setup)
  (org-capture))

(provide 'blueprint-capture)
;;; blueprint-capture.el ends here
