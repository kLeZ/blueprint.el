;;; blueprint-runtime.el --- Runtime behavior management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive commands to add runtime behavior flows to arc42.org.
;; Each flow includes both a use case diagram (who does what) and a
;; sequence diagram (how messages are exchanged over time), each
;; accompanied by a prose description to give context to the diagram.
;;
;;   `blueprint-runtime-add-flow' -- add a level-2 flow with UC + seq diagrams
;;
;; Flows are inserted under the runtime section, found by its
;; :BLUEPRINT_SECTION: property or its title (see
;; `blueprint--section-find').  The section is created at the end of
;; the file if it is absent, in the document language.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

;;; --- Internal helpers ---

(defun blueprint--runtime-slugify (name)
  "Return a slug for NAME: lowercase, non-alphanumeric replaced with hyphens.
Leading and trailing hyphens are stripped."
  (string-trim
   (replace-regexp-in-string
    "-+" "-"
    (replace-regexp-in-string "[^a-z0-9]" "-" (downcase name)))
   "-+" "-+"))

(defun blueprint--runtime-list-flows (file)
  "Return the names of the runtime flows (level 2) in FILE.
They are the children of the runtime section (`runtime', see
`blueprint--section-find')."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((parent (blueprint--section-find 'runtime 1))
            flows)
        (when parent
          (org-element-map parent 'headline
            (lambda (hl)
              (when (= (org-element-property :level hl) 2)
                (push (org-element-property :raw-value hl) flows)))))
        (nreverse flows)))))

;;; --- Public commands ---

;;;###autoload
(defun blueprint-runtime-add-flow (component flow-name)
  "Add a runtime flow FLOW-NAME with use case and sequence diagrams to COMPONENT.
Inserts a level-2 heading under the runtime section of arc42.org.

Each flow includes:
  - A prose description (objective, actors, preconditions, context)
  - A use case sub-heading with PlantUML use case diagram and
    a description targeted at non-technical stakeholders
  - A sequence sub-heading with PlantUML sequence diagram and
    a description targeted at technical teams

Creates the runtime section if absent.  The text is in the
document language."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Flow name: ")))
  (let ((file (blueprint--component-file component)))
    (unless file (user-error "Component %s not found" component))
    (let* ((dir (gethash component (blueprint--components)))
           (comp-id (file-name-nondirectory (directory-file-name dir)))
           (slug (blueprint--runtime-slugify flow-name))
           (anchor (format "%s-flow-%s" comp-id slug))
           (uc-file (format "%s-uc-%s.svg" comp-id slug))
           (seq-file (format "%s-seq-%s.svg" comp-id slug))
           (content (blueprint--snippet
                     "runtime-flow"
                     `(("NAME" . ,flow-name) ("ANCHOR" . ,anchor)
                       ("UC_FILE" . ,uc-file) ("COMPONENT" . ,component)
                       ("SEQ_FILE" . ,seq-file))))
           (buf (find-file-noselect file)))
      (with-current-buffer buf
        (blueprint--section-ensure-end 'runtime)
        (blueprint--insert-aligned content)
        (save-buffer))
      (switch-to-buffer buf)
      (message "Added flow '%s' to %s" flow-name component))))

;;;###autoload
(defun blueprint-runtime-add-process (component process-name)
  "Add business process PROCESS-NAME with a swimlane activity diagram to COMPONENT.
Inserts a level-2 heading under the business processes section of
arc42.org, with a PlantUML activity diagram using swimlanes (`|Actor|') to show
which actor performs each step of a multi-actor business process --
distinct from `blueprint-runtime-add-flow', whose UC/sequence diagrams
describe how a single flow's messages move between system components,
not between business actors over time.

Creates the section if absent."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Process name: ")))
  (let ((file (blueprint--component-file component)))
    (unless file (user-error "Component %s not found" component))
    (let* ((dir (gethash component (blueprint--components)))
           (comp-id (file-name-nondirectory (directory-file-name dir)))
           (slug (blueprint--runtime-slugify process-name))
           (anchor (format "%s-process-%s" comp-id slug))
           (svg-file (format "%s-process-%s.svg" comp-id slug))
           (content (blueprint--snippet
                     "runtime-process"
                     `(("NAME" . ,process-name) ("ANCHOR" . ,anchor)
                       ("SVG_FILE" . ,svg-file))))
           (buf (find-file-noselect file)))
      (with-current-buffer buf
        (blueprint--section-ensure-end 'business-processes)
        (blueprint--insert-aligned content)
        (save-buffer))
      (switch-to-buffer buf)
      (message "Added business process '%s' to %s" process-name component))))

(provide 'blueprint-runtime)
;;; blueprint-runtime.el ends here
