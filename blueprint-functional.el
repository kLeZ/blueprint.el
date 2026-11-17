;;; blueprint-functional.el --- Functional spec management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive commands to incrementally build a component's functional.org.
;; For large or monolithic components the blank template is overwhelming; these
;; commands let the analyst focus on one piece at a time:
;;
;;   `blueprint-functional-add-area'    -- add a level-2 functional area
;;   `blueprint-functional-add-feature' -- add a level-3 feature under an area
;;   `blueprint-functional-add-entity'  -- add a level-2 domain entity
;;
;; Each command opens the file and positions the cursor at the inserted content.
;;
;; Insertion relies on a two-step strategy used throughout the codebase:
;;   1. org-element locates the target heading (`:contents-begin').
;;   2. A regex search finds the next sibling heading (same or higher level).
;;   The new content is inserted just before that sibling (or at EOF).

;;; Code:

(require 'blueprint-core)
(require 'org-element)

;;; --- Internal helpers ---

(defun blueprint--functional-file (component)
  "Return path to functional.org for COMPONENT, or signal an error.
Signals an error if the component does not exist or has no functional.org."
  (let* ((comps (blueprint--components))
         (dir (gethash component comps)))
    (unless dir (user-error "Component %s not found" component))
    (let ((file (expand-file-name "functional.org" dir)))
      (unless (file-exists-p file)
        (user-error "No functional.org for component %s; was it created with the functional template?" component))
      file)))

(defun blueprint--func-slugify (name)
  "Return a slug for NAME: lowercase, non-alphanumeric replaced with hyphens.
Leading and trailing hyphens are stripped."
  (string-trim
   (replace-regexp-in-string
    "-+" "-"
    (replace-regexp-in-string "[^a-z0-9]" "-" (downcase name)))
   "-+" "-+"))

(defun blueprint--func-find-heading (level title)
  "Return `:contents-begin' of heading TITLE at LEVEL in the current buffer.
Uses org-element.  Falls back to `:end' if the heading has no body.
Returns nil if the heading is not found."
  (let (result)
    (org-element-map (org-element-parse-buffer 'headline) 'headline
      (lambda (hl)
        (when (and (= (org-element-property :level hl) level)
                   (string= (org-element-property :raw-value hl) title))
          (setq result (or (org-element-property :contents-begin hl)
                           (org-element-property :end hl)))))
      nil t)
    result))

(defun blueprint--func-goto-section-end (level title)
  "Move point to the insertion position at the end of heading TITLE at LEVEL.
Finds the next heading at LEVEL or above and positions before it, or at EOF.
Returns t when the heading is found, nil otherwise.  For the sections
the code knows, use `blueprint--section-goto-end', which also finds
them by property and in any language."
  (let ((pos (blueprint--func-find-heading level title)))
    (when pos
      (goto-char pos)
      (let ((next (save-excursion
                    (when (re-search-forward
                           (format "^\\*\\{1,%d\\} " level) nil t)
                      (line-beginning-position)))))
        (goto-char (or next (point-max))))
      t)))

(defun blueprint--func-list-children (file section)
  "Return the level-2 heading names under SECTION (an id) in FILE.
SECTION is found by property or title (`blueprint--section-find')."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((parent (blueprint--section-find section 1))
            names)
        (when parent
          (org-element-map parent 'headline
            (lambda (hl)
              (when (= (org-element-property :level hl) 2)
                (push (org-element-property :raw-value hl) names)))))
        (nreverse names)))))

(defun blueprint--func-list-areas (file)
  "Return the names of the functional areas (level 2) in FILE."
  (blueprint--func-list-children file 'functional-areas))

(defun blueprint--func-list-integrations (file)
  "Return the names of the integration points (level 2) in FILE."
  (blueprint--func-list-children file 'integration-points))

;;; --- Public commands ---

;;;###autoload
(defun blueprint-functional-add-area (component area-name)
  "Add a new functional area AREA-NAME to COMPONENT's functional.org.
Inserts a level-2 heading with org anchor and placeholder content under
the functional areas section (`functional-areas', see
`blueprint--section-find').  Creates the section if absent."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Area name: ")))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify area-name))
         (anchor (format "%s-area-%s" comp-id slug))
         (content (blueprint--snippet "functional-area"
                                  `(("NAME" . ,area-name) ("ANCHOR" . ,anchor))))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (blueprint--section-ensure-end 'functional-areas)
      (blueprint--insert-aligned content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added area '%s' to %s" area-name component)))

;;;###autoload
(defun blueprint-functional-add-feature (component area feature-name)
  "Add a new feature FEATURE-NAME under AREA in COMPONENT's functional.org.
Inserts a level-3 heading with the standard skeleton (purpose, input,
output, business rules, validation rules, edge cases), in the document
language.
Signals an error if AREA does not exist in the file."
  (interactive
   (let* ((names (hash-table-keys (blueprint--components)))
          (comp (completing-read "Component: " names nil t))
          (dir (gethash comp (blueprint--components)))
          (func-file (when dir (expand-file-name "functional.org" dir)))
          (areas (blueprint--func-list-areas func-file)))
     (unless areas
       (user-error "No areas in %s; add one first with blueprint-functional-add-area"
                   comp))
     (list comp
           (completing-read "Area: " areas nil t)
           (read-string "Feature name: "))))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify feature-name))
         (anchor (format "%s-func-%s" comp-id slug))
         (content (blueprint--snippet "functional-feature"
                                  `(("NAME" . ,feature-name) ("ANCHOR" . ,anchor))))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (blueprint--func-goto-section-end 2 area)
        (user-error "Area '%s' not found in %s; add it first with blueprint-functional-add-area"
                    area component))
      (blueprint--insert-aligned content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added feature '%s' under area '%s' in %s" feature-name area component)))

;;;###autoload
(defun blueprint-functional-add-entity (component entity-name)
  "Add a new domain entity ENTITY-NAME to COMPONENT's functional.org.
Inserts a level-2 heading with attribute table (including a relation
column) and a logical representation sub-heading with a PlantUML ER
skeleton, under the domain entities section (`domain-entities').
Creates the section if absent.

New entities are always inserted BEFORE the overall ER diagram (the
`er-diagram' section, if present) so that the general diagram remains
the last item in the section."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Entity name: ")))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify entity-name))
         (anchor (format "%s-entity-%s" comp-id slug))
         (er-anchor (format "%s-entity-%s-er" comp-id slug))
         (er-file (format "%s-er-%s.svg" comp-id slug))
         (content (blueprint--snippet "functional-entity"
                                  `(("NAME" . ,entity-name) ("ANCHOR" . ,anchor)
                                    ("ER_ANCHOR" . ,er-anchor) ("ER_FILE" . ,er-file))))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      ;; Insert before the overall ER diagram to keep it as the last item
      (let ((er-general-pos
             (let ((hl (blueprint--section-find 'er-diagram 2)))
               (and hl (org-element-property :begin hl)))))
        (if er-general-pos
            (goto-char er-general-pos)
          (blueprint--section-ensure-end 'domain-entities)))
      (blueprint--insert-aligned content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added entity '%s' to %s" entity-name component)))

;;;###autoload
(defun blueprint-functional-add-integration (component integration-name direction)
  "Add a new integration point INTEGRATION-NAME to COMPONENT's functional.org.
DIRECTION is one of \"IN\", \"OUT\", or \"IN/OUT\".
Inserts a level-2 heading with a metadata table (direction, counterpart,
protocol, authentication, frequency, SLA) and an exchange format
sub-heading with a code block placeholder, under the integration
points section (`integration-points').  Creates the section if absent."
  (interactive
   (let* ((names (hash-table-keys (blueprint--components)))
          (comp (completing-read "Component: " names nil t))
          (name (read-string "Integration name: "))
          (dir  (completing-read "Direction: " '("IN" "OUT" "IN/OUT") nil t)))
     (list comp name dir)))
  (let* ((file (blueprint--functional-file component))
         (dir-path (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir-path)))
         (slug (blueprint--func-slugify integration-name))
         (anchor (format "%s-integ-%s" comp-id slug))
         (fmt-anchor (format "%s-integ-%s-fmt" comp-id slug))
         (content (blueprint--snippet "functional-integration"
                                  `(("NAME" . ,integration-name) ("ANCHOR" . ,anchor)
                                    ("DIRECTION" . ,direction) ("FORMAT_ANCHOR" . ,fmt-anchor))))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (blueprint--section-ensure-end 'integration-points)
      (blueprint--insert-aligned content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added integration '%s' (%s) to %s" integration-name direction component)))

(provide 'blueprint-functional)
;;; blueprint-functional.el ends here
