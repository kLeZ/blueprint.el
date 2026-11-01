;;; blueprint-c4.el --- C4 diagram generation for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Generates PlantUML C4 container diagrams by reading BLUEPRINT_DEPENDS
;; keywords from each component's arc42.org file.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-sync)

(defvar blueprint-enterprise-c4-start-marker "' @@blueprint-enterprise-start@@"
  "Marker delimiting the start of the auto-generated enterprise C4 section.")

(defvar blueprint-enterprise-c4-end-marker "' @@blueprint-enterprise-end@@"
  "Marker delimiting the end of the auto-generated enterprise C4 section.")

(defconst blueprint--component-scope-values '("in-scope" "out-of-scope" "tbd")
  "Valid values for the #+BLUEPRINT_STATUS: keyword.")

(defun blueprint--component-scope-status (id)
  "Return the perimeter status of component ID.
Reads #+BLUEPRINT_STATUS: from ID's arc42.org, one of
`blueprint--component-scope-values'.  Defaults to \"in-scope\" when
the keyword is absent (components created before this feature existed)
or holds an unrecognized value, so older projects keep behaving as if
every component were in scope."
  (let* ((file (blueprint--component-file id))
         (status (blueprint--org-keyword file "BLUEPRINT_STATUS")))
    (if (member status blueprint--component-scope-values)
        status
      "in-scope")))

(defconst blueprint--component-lifecycle-values
  '("draft" "active" "deprecated" "archived")
  "Valid values for the #+BLUEPRINT_LIFECYCLE: keyword.
The life cycle of a component is a different axis from its perimeter
status (#+BLUEPRINT_STATUS:, `blueprint--component-scope-status').")

(defun blueprint--component-lifecycle-status (id)
  "Return the life-cycle status of component ID.
Reads #+BLUEPRINT_LIFECYCLE: from ID's arc42.org, one of
`blueprint--component-lifecycle-values'.  Defaults to \"active\" when
the keyword is absent (components created before this feature existed)
or holds an unrecognized value, so existing projects keep behaving as
if every component were active."
  (let* ((file (blueprint--component-file id))
         (lifecycle (blueprint--org-keyword file "BLUEPRINT_LIFECYCLE")))
    (if (member lifecycle blueprint--component-lifecycle-values)
        lifecycle
      "active")))

;;;###autoload
(defun blueprint-generate-c4 ()
  "Generate a PlantUML C4 container diagram from project dependencies.
Reads BLUEPRINT_DEPENDS keywords from each component's arc42.org file
and writes the result to c4.puml in the project root."
  (interactive)
  (let ((elements '())
        (relations '())
        (root (blueprint--root)))
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (deps (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
         (push (format "Container(%s, \"%s\", \"component\")" id id) elements)
         (when (and deps (not (string-blank-p deps)))
           (dolist (d (split-string deps))
             (push (format "Rel(%s, %s, \"uses\")" id d) relations)))))
     (blueprint--components))

    (let ((outfile (expand-file-name "c4.puml" root)))
      (with-temp-file outfile
        (insert "@startuml\n!include C4_Container.puml\n")
        (dolist (e elements) (insert e "\n"))
        (dolist (r relations) (insert r "\n"))
        (insert "@enduml\n"))
      (message "Generated %s" outfile))))

;;;###autoload
(defun blueprint-generate-enterprise-c4 ()
  "Generate a C4 L1 enterprise context diagram from all components.
Unlike `blueprint-generate-c4' (a Container-level L2 diagram written
to its own c4.puml), this is simpler -- every component becomes a
`System(...)' with no Container -- and it updates only the
auto-generated section of enterprise/context.org, between
`blueprint-enterprise-c4-start-marker' and
`blueprint-enterprise-c4-end-marker'.  External systems, users, and
any relation to them are written by hand outside those markers and
are never touched, exactly like `blueprint-sync' preserves manual
content in master.org.

Signals a user-error if enterprise/context.org is missing (run
`blueprint-init' first) or does not contain the markers (regenerate
it from the current enterprise-context.org template)."
  (interactive)
  (let ((file (expand-file-name "enterprise/context.org" (blueprint--root))))
    (unless (file-exists-p file)
      (user-error "No enterprise/context.org found; run blueprint-init first"))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (unless (search-forward blueprint-enterprise-c4-start-marker nil t)
          (user-error
           "enterprise/context.org has no %s marker; regenerate it from the enterprise-context.org template"
           blueprint-enterprise-c4-start-marker)))
      (let ((names (sort (hash-table-keys (blueprint--components)) #'string<))
            (lines '()))
        (dolist (id names)
          (push (format "System(%s, \"%s\", \"\")" id id) lines)
          (let ((deps (blueprint--org-keyword
                       (blueprint--component-file id) "BLUEPRINT_DEPENDS")))
            (when (and deps (not (string-blank-p deps)))
              (dolist (d (split-string deps))
                (push (format "Rel(%s, %s, \"uses\")" id d) lines)))))
        (blueprint--sync-section
         blueprint-enterprise-c4-start-marker
         blueprint-enterprise-c4-end-marker
         (mapconcat #'identity (nreverse lines) "\n")))
      (save-buffer))
    (message "Enterprise C4 context updated in enterprise/context.org")))

(provide 'blueprint-c4)
;;; blueprint-c4.el ends here
