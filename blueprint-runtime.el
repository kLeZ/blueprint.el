;;; blueprint-runtime.el --- Runtime behavior management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive commands to add runtime behavior flows to arc42.org.
;; Each flow includes both a use case diagram (chi fa cosa) and a
;; sequence diagram (come i messaggi si scambiano nel tempo), each
;; accompanied by a prose description to give context to the diagram.
;;
;;   `blueprint-runtime-add-flow' -- add a level-2 flow with UC + seq diagrams
;;
;; Flows are inserted under the `* Runtime Behavior' section.  The section
;; is created at the end of the file if it is absent.

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

(defun blueprint--runtime-find-heading (level title)
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

(defun blueprint--runtime-goto-section-end ()
  "Move point to the insertion position at the end of `* Runtime Behavior'.
Finds the next level-1 heading and positions before it, or at EOF.
Returns t when the section is found, nil otherwise."
  (let ((pos (blueprint--runtime-find-heading 1 "Runtime Behavior")))
    (when pos
      (goto-char pos)
      (let ((next (save-excursion
                    (when (re-search-forward "^\\* " nil t)
                      (line-beginning-position)))))
        (goto-char (or next (point-max))))
      t)))

(defun blueprint--runtime-list-flows (file)
  "Return list of level-2 flow names under `* Runtime Behavior' in FILE."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let (flows (in-runtime nil))
        (org-element-map (org-element-parse-buffer 'headline) 'headline
          (lambda (hl)
            (let ((lvl (org-element-property :level hl))
                  (raw (org-element-property :raw-value hl)))
              (cond
               ((= lvl 1) (setq in-runtime (string= raw "Runtime Behavior")))
               ((and in-runtime (= lvl 2)) (push raw flows))))))
        (nreverse flows)))))

;;; --- Public commands ---

;;;###autoload
(defun blueprint-runtime-add-flow (component flow-name)
  "Add a runtime flow FLOW-NAME with use case and sequence diagrams to COMPONENT.
Inserts a level-2 heading under `* Runtime Behavior' in arc42.org.

Each flow includes:
  - A prose description (objective, actors, preconditions, context)
  - A `*** Casi d\\='uso\\=' sub-heading with PlantUML use case diagram and
    a description targeted at non-technical stakeholders
  - A `*** Sequenza\\=' sub-heading with PlantUML sequence diagram and
    a description targeted at technical teams

Creates the `* Runtime Behavior\\=' section if absent."
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
           (content (concat
                     (format "** Flusso: %s\n<<%s>>\n[DA VALIDARE]\n\n" flow-name anchor)
                     "Descrizione del flusso: obiettivo, precondizioni, attori coinvolti e\n"
                     "vincoli di contesto rilevanti.\n\n"
                     "*** Casi d'uso\n\n"
                     "Panoramica degli attori e delle funzionalità coinvolte nel flusso.\n"
                     "Questa vista è utile per comunicare con stakeholder non tecnici.\n\n"
                     (format "#+begin_src plantuml :file %s\n" uc-file)
                     "@startuml\n"
                     "left to right direction\n"
                     "actor \"Utente\" as u\n"
                     (format "rectangle \"%s\" {\n" component)
                     "  usecase \"Caso d'uso 1\" as uc1\n"
                     "  usecase \"Caso d'uso 2\" as uc2\n"
                     "}\n"
                     "u --> uc1\n"
                     "u --> uc2\n"
                     "@enduml\n"
                     "#+end_src\n\n"
                     "*** Sequenza\n\n"
                     "Dettaglio temporale degli scambi di messaggi per il flusso.\n"
                     "Questa vista è utile per i team tecnici e per la documentazione delle API.\n\n"
                     (format "#+begin_src plantuml :file %s\n" seq-file)
                     "@startuml\n"
                     "participant \"A\" as a\n"
                     "participant \"B\" as b\n"
                     "a -> b : messaggio\n"
                     "b --> a : risposta\n"
                     "@enduml\n"
                     "#+end_src\n\n"))
           (buf (find-file-noselect file)))
      (with-current-buffer buf
        (unless (blueprint--runtime-goto-section-end)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert "* Runtime Behavior\n\n"))
        (insert content)
        (save-buffer))
      (switch-to-buffer buf)
      (message "Added flow '%s' to %s" flow-name component))))

(provide 'blueprint-runtime)
;;; blueprint-runtime.el ends here
