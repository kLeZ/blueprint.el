;;; blueprint-wizard.el --- Guided wizards for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive wizards for project onboarding and component creation
;; with pre-filled templates.

;;; Code:

(require 'blueprint-core)

;;;###autoload
(defun blueprint-wizard-component ()
  "Interactive wizard to create a component with pre-filled content.
Prompts for name, responsibility, owner, tech stack, and initial
dependencies, then generates a populated arc42.org file."
  (interactive)
  (let* ((name (read-string "Component name: "))
         (responsibility (read-string "Responsibility (one line): "))
         (owner (read-string "Owner / team: "))
         (tech (read-string "Tech stack: "))
         (deps (read-string "Dependencies (space-separated): "))
         (dir (expand-file-name name
                                (expand-file-name ".blueprint/components"
                                                  (blueprint--root))))
         (file (expand-file-name "arc42.org" dir))
         (content (blueprint--template "component.org")))
    (setq content (replace-regexp-in-string "{{NAME}}" name content t t))
    ;; Replace empty BLUEPRINT_DEPENDS with provided deps
    (setq content (replace-regexp-in-string
                   "^#\\+BLUEPRINT_DEPENDS:.*$"
                   (format "#+BLUEPRINT_DEPENDS: %s" deps)
                   content))
    ;; Insert pre-filled content after relevant headings
    (when (not (string-empty-p responsibility))
      (setq content (replace-regexp-in-string
                     "\\(\\* Responsibility\\)\n"
                     (format "\\1\n\n%s\n" responsibility)
                     content)))
    (make-directory dir t)
    (with-temp-file file
      (insert content)
      ;; Add owner and tech as properties if provided
      (goto-char (point-min))
      (when (re-search-forward "^#\\+BLUEPRINT_DEPENDS:" nil t)
        (end-of-line)
        (when (not (string-empty-p owner))
          (insert (format "\n#+BLUEPRINT_OWNER: %s" owner)))
        (when (not (string-empty-p tech))
          (insert (format "\n#+BLUEPRINT_TECH: %s" tech)))))
    (find-file file)
    (message "Created component %s with wizard" name)))

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
