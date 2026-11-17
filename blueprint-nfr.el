;;; blueprint-nfr.el --- NFR management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
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

;;; --- Quality scenarios ---

(defcustom blueprint-nfr-quality-attributes nil
  "Quality attributes offered by `blueprint-nfr-add-quality-scenario'.
When nil, the list of the document language (security, reliability,
availability...)."
  :type '(choice (const :tag "The list of the document language" nil)
                 (repeat string))
  :group 'blueprint)

(defun blueprint--nfr-quality-attributes ()
  "Return the quality attributes to offer for completion."
  (or blueprint-nfr-quality-attributes
      (blueprint--l10n-list 'nfr-quality-attributes)))

;;;###autoload
(defun blueprint-nfr-add-quality-scenario (attribute name)
  "Add a quality scenario for ATTRIBUTE with NAME to nfr/quality-scenarios.org.
ATTRIBUTE is completed from `blueprint-nfr-quality-attributes'.  The
scenario goes at the end of the quality scenarios section, created
if absent; its fields are in the document language."
  (interactive
   (list
    (completing-read "Quality attribute: " (blueprint--nfr-quality-attributes)
                     nil nil)
    (read-string "Scenario name: ")))
  (let ((file (blueprint--nfr-file "quality-scenarios.org")))
    (unless (file-exists-p file)
      (user-error "nfr/quality-scenarios.org not found -- run blueprint-init first"))
    (let ((entry (blueprint--snippet "quality-scenario"
                                    `(("NAME" . ,name) ("ATTRIBUTE" . ,attribute)))))
      (with-current-buffer (find-file-noselect file)
        (blueprint--section-ensure-end 'quality-scenarios)
        (unless (bolp) (insert "\n"))
        (insert entry)
        (save-buffer))
      (find-file file)
      (message "Added quality scenario: %s (%s)" name attribute))))

;;; --- Constraints ---

(defconst blueprint--nfr-constraint-types
  '(("technical"      constraints-technical      4 "tecnico")
    ("organizational" constraints-organizational 3 "organizzativo")
    ("regulatory"     constraints-regulatory     3 "normativo"))
  "Constraint types: (NAME SECTION CELLS LEGACY-NAME).
SECTION is the section id of the type in constraints.org, CELLS the
number of cells after the constraint text in its table.  LEGACY-NAME
is the Italian name earlier versions took as argument, still
accepted.")

(defun blueprint--nfr-constraint-type (type)
  "Return the entry of `blueprint--nfr-constraint-types' for TYPE.
TYPE is the English name or the legacy Italian one."
  (or (cl-find-if (lambda (e) (member type (list (car e) (nth 3 e))))
                  blueprint--nfr-constraint-types)
      (user-error "Unknown constraint type: %s" type)))

(defun blueprint--nfr-constraint-row (type text)
  "Return an org-table row for a constraint of TYPE with TEXT as the first column.
The other cells hold the to-validate marker."
  (let ((cells (nth 2 (blueprint--nfr-constraint-type type))))
    (concat "| " text
            (apply #'concat (make-list cells
                                       (format " | %s" blueprint-marker-to-validate)))
            " |\n")))

;;;###autoload
(defun blueprint-nfr-add-constraint (type text)
  "Add a constraint of TYPE with TEXT to nfr/constraints.org.
TYPE is one of \"technical\", \"organizational\", \"regulatory\" (the
Italian \"tecnico\", \"organizzativo\", \"normativo\" are accepted
too).  The row goes into the table of the section of that type."
  (interactive
   (list
    (completing-read "Constraint type: "
                     (mapcar #'car blueprint--nfr-constraint-types) nil t)
    (read-string "Constraint: ")))
  (let ((file (blueprint--nfr-file "constraints.org"))
        (entry (blueprint--nfr-constraint-type type)))
    (unless (file-exists-p file)
      (user-error "nfr/constraints.org not found -- run blueprint-init first"))
    (with-current-buffer (find-file-noselect file)
      (blueprint--section-append-row
       (nth 1 entry) (blueprint--nfr-constraint-row type text) 2)
      (save-buffer))
    (find-file file)
    (message "Added %s constraint: %s" (car entry) text)))

;;; --- Risks ---

(defun blueprint--nfr-next-risk-id ()
  "Return the next risk ID (R-NNN) based on existing entries in nfr/risks.org.
Scans only within the risk register section (`risk-register'), not
the whole file: the :noexport: compilation guide above it shows
R-001/R-002 as worked examples, and without this boundary they are
indistinguishable from real entries, so a fresh project's first real
risk would be numbered R-003 instead of R-001."
  (let ((file (blueprint--nfr-file "risks.org"))
        (max-num 0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((bounds (blueprint--section-bounds 'risk-register 1)))
          (when bounds
            (goto-char (car bounds))
            (while (re-search-forward "| R-\\([0-9]\\{3\\}\\)" (cdr bounds) t)
              (let ((n (string-to-number (match-string 1))))
                (when (> n max-num) (setq max-num n))))))))
    (format "R-%03d" (1+ max-num))))

(defun blueprint--nfr-risk-level (probability impact)
  "Calculate the risk level string from PROBABILITY and IMPACT strings.
Both are values of the risk register (high, medium, low) in any
language; the level is in the document language: critical when both
are high, then high, medium and low."
  (let* ((p (or (blueprint--l10n-rank probability 'nfr-probabilities) 2))
         (i (or (blueprint--l10n-rank impact 'nfr-impacts) 2))
         (level (cond ((and (= p 0) (= i 0)) 0)
                      ((or (and (= p 0) (= i 1)) (and (= p 1) (= i 0))) 1)
                      ((or (and (= p 2) (= i 0)) (and (= p 1) (= i 1))
                           (and (= p 0) (= i 2)))
                       2)
                      (t 3))))
    (nth level (blueprint--l10n-list 'nfr-risk-levels))))

;;;###autoload
(defun blueprint-nfr-add-risk (description component probability impact)
  "Add a risk entry to nfr/risks.org with an auto-incremented ID.
DESCRIPTION is the risk text; COMPONENT is the affected component (may be
empty for cross-cutting risks); PROBABILITY and IMPACT drive automatic
level calculation.  The values are offered in the document language."
  (interactive
   (list
    (read-string "Risk description: ")
    (read-string "Affected component(s) [blank = cross-cutting]: ")
    (completing-read "Probability: " (blueprint--l10n-list 'nfr-probabilities) nil t)
    (completing-read "Impact: " (blueprint--l10n-list 'nfr-impacts) nil t)))
  (let ((file (blueprint--nfr-file "risks.org")))
    (unless (file-exists-p file)
      (user-error "nfr/risks.org not found -- run blueprint-init first"))
    (let* ((id    (blueprint--nfr-next-risk-id))
           (level (blueprint--nfr-risk-level probability impact))
           (comp  (if (string-empty-p component)
                      (blueprint--l10n 'nfr-cross-cutting)
                    component))
           (row   (format
                   "| %s | %s | %s | %s | %s | %s | %s | %s | |\n"
                   id description comp probability impact level
                   blueprint-marker-to-validate blueprint-marker-to-validate)))
      (with-current-buffer (find-file-noselect file)
        (unless (blueprint--section-find 'risk-register 1)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (blueprint--section-heading 'risk-register 1)
                  (blueprint--l10n 'nfr-risk-table-header) "\n"))
        (blueprint--section-append-row 'risk-register row 1)
        (save-buffer))
      (find-file file)
      (message "Added risk %s [%s]: %s" id level description))))

(provide 'blueprint-nfr)
;;; blueprint-nfr.el ends here
