;;; blueprint-nfr.el --- NFR management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive commands for populating the NFR files created by
;; `blueprint-init':
;;
;;   nfr/quality-scenarios.org -- quality attribute scenarios (arc42 style)
;;   nfr/constraints.org       -- technical, organisational, regulatory constraints
;;   nfr/risks.org             -- cross-cutting risk register
;;
;; These files are project-wide (not per-component).  Component-level risks
;; live in the Risks section of each component's arc42.org.

;;; Code:

(require 'blueprint-core)

;;; --- Path helper ---

(defun blueprint--nfr-file (name)
  "Return the path to the NFR file NAME in the current project's nfr/ directory."
  (expand-file-name (concat "nfr/" name) (blueprint--root)))

;;; --- Shared insertion helper ---

(defun blueprint--nfr-insert-row-in-section (section-heading row)
  "Append ROW after the last org-table line under SECTION-HEADING.
Works on the current buffer.  If the section is absent, appends both
the heading and the row at the end of the buffer."
  (goto-char (point-min))
  (let ((last-pipe-pos nil))
    (when (re-search-forward (regexp-quote section-heading) nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\*" nil t)
                               (match-beginning 0)
                             (point-max)))))
        (while (re-search-forward "^|" section-end t)
          (setq last-pipe-pos (line-end-position)))))
    (if last-pipe-pos
        (progn (goto-char last-pipe-pos) (insert "\n" row))
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert row))))

;;; --- Quality scenarios ---

(defcustom blueprint-nfr-quality-attributes
  '("Performance" "Sicurezza" "Affidabilità" "Disponibilità"
    "Manutenibilità" "Scalabilità" "Portabilità" "Interoperabilità")
  "Predefined quality attributes offered for completion in `blueprint-nfr-add-quality-scenario'."
  :type '(repeat string)
  :group 'blueprint)

(defun blueprint--nfr-goto-end-of-quality-scenarios ()
  "Move point to the insertion position for a new quality scenario.
Ensures the `* Scenari di qualità' section exists, then navigates to
its end (just before the next top-level heading, or EOF)."
  (goto-char (point-min))
  (unless (re-search-forward "^\\* Scenari di qualità" nil t)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* Scenari di qualità\n"))
  (goto-char (point-min))
  (re-search-forward "^\\* Scenari di qualità" nil t)
  (if (re-search-forward "^\\*[^*]" nil t)
      (goto-char (match-beginning 0))
    (goto-char (point-max))))

;;;###autoload
(defun blueprint-nfr-add-quality-scenario (attribute name)
  "Add a quality scenario for ATTRIBUTE with NAME to nfr/quality-scenarios.org.
ATTRIBUTE is completed from `blueprint-nfr-quality-attributes'."
  (interactive
   (list
    (completing-read "Quality attribute: " blueprint-nfr-quality-attributes nil nil)
    (read-string "Scenario name: ")))
  (let ((file (blueprint--nfr-file "quality-scenarios.org")))
    (unless (file-exists-p file)
      (user-error "nfr/quality-scenarios.org not found -- run blueprint-init first"))
    (let ((entry (concat
                  (format "** %s\n" name)
                  (format "- *Attributo di qualità*: %s\n" attribute)
                  "- *Contesto*: [DA VALIDARE]\n"
                  "- *Stimolo*: [DA VALIDARE]\n"
                  "- *Risposta attesa*: [DA VALIDARE]\n"
                  "- *Misura*: [DA VALIDARE]\n"
                  "- *Priorità*: [Alta / Media / Bassa]\n"
                  "- *Fonte*: [DA VALIDARE]\n\n")))
      (with-current-buffer (find-file-noselect file)
        (blueprint--nfr-goto-end-of-quality-scenarios)
        (unless (bolp) (insert "\n"))
        (insert entry)
        (save-buffer))
      (find-file file)
      (message "Added quality scenario: %s (%s)" name attribute))))

;;; --- Constraints ---

(defun blueprint--nfr-constraint-section-heading (type)
  "Return the Org heading for constraint TYPE (tecnico/organizzativo/normativo)."
  (cond
   ((string= type "tecnico")       "** Vincoli tecnici")
   ((string= type "organizzativo") "** Vincoli organizzativi")
   ((string= type "normativo")     "** Vincoli normativi e di compliance")
   (t (user-error "Unknown constraint type: %s" type))))

(defun blueprint--nfr-constraint-row (type text)
  "Return an org-table row for a constraint of TYPE with TEXT as the first column."
  (cond
   ((string= type "tecnico")
    (format "| %s | [DA VALIDARE] | [DA VALIDARE] | [DA VALIDARE] | [DA VALIDARE] |\n" text))
   ((string= type "organizzativo")
    (format "| %s | [DA VALIDARE] | [DA VALIDARE] | [DA VALIDARE] |\n" text))
   ((string= type "normativo")
    (format "| %s | [DA VALIDARE] | [DA VALIDARE] | [DA VALIDARE] |\n" text))
   (t "")))

;;;###autoload
(defun blueprint-nfr-add-constraint (type text)
  "Add a constraint of TYPE with TEXT to nfr/constraints.org.
TYPE is one of \"tecnico\", \"organizzativo\", \"normativo\"."
  (interactive
   (list
    (completing-read "Constraint type: "
                     '("tecnico" "organizzativo" "normativo") nil t)
    (read-string "Constraint: ")))
  (let ((file (blueprint--nfr-file "constraints.org")))
    (unless (file-exists-p file)
      (user-error "nfr/constraints.org not found -- run blueprint-init first"))
    (let ((heading (blueprint--nfr-constraint-section-heading type))
          (row (blueprint--nfr-constraint-row type text)))
      (with-current-buffer (find-file-noselect file)
        (blueprint--nfr-insert-row-in-section heading row)
        (save-buffer))
      (find-file file)
      (message "Added %s constraint: %s" type text))))

;;; --- Risks ---

(defun blueprint--nfr-next-risk-id ()
  "Return the next risk ID (R-NNN) based on existing entries in nfr/risks.org."
  (let ((file (blueprint--nfr-file "risks.org"))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "| R-\\([0-9]\\{3\\}\\)" nil t)
          (let ((n (string-to-number (match-string 1))))
            (when (> n max-num) (setq max-num n))))))
    (format "R-%03d" (1+ max-num))))

(defun blueprint--nfr-risk-level (probability impact)
  "Calculate the risk level string from PROBABILITY and IMPACT strings."
  (cond
   ((and (string= probability "Alta") (string= impact "Alto"))
    "Critico")
   ((or (and (string= probability "Alta") (string= impact "Medio"))
        (and (string= probability "Media") (string= impact "Alto")))
    "Alto")
   ((or (and (string= probability "Bassa") (string= impact "Alto"))
        (and (string= probability "Media") (string= impact "Medio"))
        (and (string= probability "Alta") (string= impact "Basso")))
    "Medio")
   (t "Basso")))

;;;###autoload
(defun blueprint-nfr-add-risk (description component probability impact)
  "Add a risk entry to nfr/risks.org with an auto-incremented ID.
DESCRIPTION is the risk text; COMPONENT is the affected component (may be
empty for cross-cutting risks); PROBABILITY and IMPACT drive automatic
level calculation."
  (interactive
   (list
    (read-string "Risk description: ")
    (read-string "Affected component(s) [blank = cross-cutting]: ")
    (completing-read "Probability: " '("Alta" "Media" "Bassa") nil t)
    (completing-read "Impact: " '("Alto" "Medio" "Basso") nil t)))
  (let ((file (blueprint--nfr-file "risks.org")))
    (unless (file-exists-p file)
      (user-error "nfr/risks.org not found -- run blueprint-init first"))
    (let* ((id    (blueprint--nfr-next-risk-id))
           (level (blueprint--nfr-risk-level probability impact))
           (comp  (if (string-empty-p component) "(trasversale)" component))
           (row   (format
                   "| %s | %s | %s | %s | %s | %s | [DA VALIDARE] | [DA VALIDARE] | |\n"
                   id description comp probability impact level)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (unless (re-search-forward "^\\* Registro dei rischi" nil t)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert "* Registro dei rischi\n| ID | Rischio | Componente/i | Probabilità | Impatto | Livello | Mitigazione | Owner | Note |\n|-\n"))
        ;; Find end of risk table
        (let ((last-pipe-pos nil)
              (section-end (save-excursion
                             (if (re-search-forward "^\\*[^*]" nil t)
                                 (match-beginning 0)
                               (point-max)))))
          (goto-char (point-min))
          (re-search-forward "^\\* Registro dei rischi" nil t)
          (while (re-search-forward "^|" section-end t)
            (setq last-pipe-pos (line-end-position)))
          (if last-pipe-pos
              (progn (goto-char last-pipe-pos) (insert "\n" row))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert row)))
        (save-buffer))
      (find-file file)
      (message "Added risk %s [%s]: %s" id level description))))

(provide 'blueprint-nfr)
;;; blueprint-nfr.el ends here
