;;; blueprint-wizard.el --- Guided wizards for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive wizards for project onboarding and component creation
;; with pre-filled templates.

;;; Code:

(require 'blueprint-core)

(declare-function blueprint-template-migrate "blueprint-migrate" ())
(declare-function blueprint-dashboard "blueprint-dashboard" ())

;;;###autoload
(defun blueprint-wizard-component ()
  "Interactive wizard to create a component with pre-filled content.
Prompts for name, responsibility, owner, tech stack, and initial
dependencies, then generates a populated arc42.org file.

The component directory name is derived from the slugified component
name (lowercase, hyphens replacing non-alphanumeric characters)."
  (interactive)
  (let* ((name (read-string "Component name: "))
         (id (replace-regexp-in-string "[^a-zA-Z0-9-]" "-" (downcase name)))
         (responsibility (read-string "Responsibility (one line): "))
         (owner (read-string "Owner / team: "))
         (tech (read-string "Tech stack: "))
         (deps (read-string "Dependencies (space-separated): "))
         (date (format-time-string "%Y-%m-%d"))
         (dir (expand-file-name id
                                (expand-file-name ".blueprint/components"
                                                  (blueprint--root))))
         (file (expand-file-name "arc42.org" dir))
         (content (blueprint--template "component.org")))
    (setq content (replace-regexp-in-string "{{NAME}}" name content t t))
    (setq content (replace-regexp-in-string "{{ID}}" id content t t))
    (setq content (replace-regexp-in-string "{{DATE}}" date content t t))
    ;; Replace empty BLUEPRINT_DEPENDS with provided deps
    (setq content (replace-regexp-in-string
                   "^#\\+BLUEPRINT_DEPENDS:.*$"
                   (format "#+BLUEPRINT_DEPENDS: %s" deps)
                   content))
    ;; Insert pre-filled content after Responsibility heading
    (when (not (string-empty-p responsibility))
      (setq content (replace-regexp-in-string
                     "\\(\\* Responsibility\\)\n"
                     (format "\\1\n\n%s\n" responsibility)
                     content)))
    (make-directory dir t)
    (with-temp-file file
      (insert content)
      ;; Fill BLUEPRINT_OWNER and BLUEPRINT_TECH keywords if provided
      (goto-char (point-min))
      (when (re-search-forward "^#\\+BLUEPRINT_OWNER:.*$" nil t)
        (when (not (string-empty-p owner))
          (replace-match (format "#+BLUEPRINT_OWNER: %s" owner))))
      (goto-char (point-min))
      (when (re-search-forward "^#\\+BLUEPRINT_TECH:.*$" nil t)
        (when (not (string-empty-p tech))
          (replace-match (format "#+BLUEPRINT_TECH: %s" tech)))))
    (find-file file)
    (message "Created component %s (id: %s) with wizard" name id)))

;;;###autoload
(defun blueprint-wizard-init ()
  "Guided project setup wizard.
Walks through project initialization, first component creation,
template migration, and opens the dashboard."
  (interactive)
  (message "=== Blueprint Project Setup Wizard ===")
  ;; Step 1: Initialize
  (blueprint-init)
  ;; Step 2: Optionally create first component
  (when (y-or-n-p "Create a first component? ")
    (blueprint-wizard-component))
  ;; Step 3: Migrate templates
  (when (y-or-n-p "Migrate system templates to project? ")
    (require 'blueprint-migrate)
    (blueprint-template-migrate))
  ;; Step 4: Open dashboard
  (when (y-or-n-p "Open the dashboard? ")
    (require 'blueprint-dashboard)
    (blueprint-dashboard))
  (message "Setup complete!"))

(provide 'blueprint-wizard)
;;; blueprint-wizard.el ends here
