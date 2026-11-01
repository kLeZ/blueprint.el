;;; blueprint-delivery.el --- Pre-delivery checklist for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; `blueprint-pre-delivery-check' produces a structured report showing
;; whether the current project is ready to be delivered to the client.
;;
;; Checks performed, all on the document only (master.org and the
;; files it includes, see `blueprint--document-files'):
;;   - Health score vs. configurable threshold
;;   - Count of [DA VALIDARE] markers in the document
;;   - Count of [DA REVISIONARE] markers in the document
;;   - Lint (components, and content of every file of the document)
;;   - Master file existence and sync marker presence
;;
;; The report also shows the number of [FINDING] markers, for
;; information only: a finding is a result the assessment delivers
;; (weight 0 in the health score), so it never counts as an issue
;; and never changes the outcome.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-lint)

;; `blueprint-delivery-score-threshold' is defined in blueprint-health.el
;; (which this module requires): the health-colored graphs use the same
;; threshold, so a customized delivery threshold is followed everywhere.

(defun blueprint--delivery-count-marker (marker)
  "Return the number of MARKER occurrences in the document.
MARKER is one of the literal markers of `blueprint--health-weights'
\(\"[DA VALIDARE]\", \"[FINDING]\"...).  The document is master.org and
the files it includes (see `blueprint--document-files'); only
exported text counts.  The count is the one of the dashboard rows and
of `blueprint-health-score'."
  (let ((re (car (cl-find-if (lambda (entry)
                               (string-match-p (concat "\\`" (car entry) "\\'")
                                               marker))
                             blueprint--health-weights))))
    (unless re
      (error "Unknown marker %s" marker))
    (blueprint--health-marker-count
     (plist-get (blueprint--document-health-summary) :counts) re)))

(defun blueprint--delivery-check-master-sync ()
  "Return t if master.org exists and contains blueprint sync markers."
  (let ((master (blueprint--master-file)))
    (and (file-exists-p master)
         (with-temp-buffer
           (insert-file-contents master)
           (goto-char (point-min))
           (re-search-forward "@@blueprint-sync-start@@" nil t)))))

(defun blueprint--delivery-collect-lint-warnings ()
  "Return the number of lint warnings, see `blueprint--lint-project'."
  (length (blueprint--lint-project)))

(defconst blueprint--delivery-info-badge "[INFO]"
  "Badge of report rows shown for information, outside the outcome.")

(defun blueprint--delivery-status (value threshold &optional invert)
  "Return a status string and indicator for VALUE vs THRESHOLD.
If INVERT is nil: OK when value >= threshold, WARN otherwise.
If INVERT is non-nil: OK when value <= threshold, WARN otherwise."
  (let ((ok (if invert (<= value threshold) (>= value threshold))))
    (if ok
        (cons "OK  " "[OK]")
      (cons "WARN" "[ATTENZIONE]"))))

;;;###autoload
(defun blueprint-pre-delivery-check ()
  "Run pre-delivery checks and display a readiness report.
Checks health score, unresolved methodology markers ([DA VALIDARE],
[DA REVISIONARE]), lint warnings, and master file synchronisation.
Markers are counted only in the document: master.org and the files
it includes, recursively (see `blueprint--document-files'); notes,
knowledge base and other Org files of the project do not count.
The health score threshold is controlled by
`blueprint-delivery-score-threshold'.  The number of [FINDING]
markers is shown with an [INFO] badge: findings are results to
deliver, not open points, so they never raise a warning or change
the outcome."
  (interactive)
  (let* ((score        (blueprint-health-score))
         (da-validare  (blueprint--delivery-count-marker "[DA VALIDARE]"))
         (da-revis     (blueprint--delivery-count-marker "[DA REVISIONARE]"))
         (findings     (blueprint--delivery-count-marker "[FINDING]"))
         (lint-warns   (blueprint--delivery-collect-lint-warnings))
         (master-ok    (blueprint--delivery-check-master-sync))
         ;; status pairs (label . badge)
         (s-score      (blueprint--delivery-status score blueprint-delivery-score-threshold))
         (s-dv         (blueprint--delivery-status da-validare 0 t))
         (s-dr         (blueprint--delivery-status da-revis 0 t))
         (s-lint       (blueprint--delivery-status lint-warns 0 t))
         (s-master     (if master-ok (cons "OK  " "[OK]") (cons "WARN" "[ATTENZIONE]")))
         (all-ok       (cl-every (lambda (s) (string= (car s) "OK  "))
                                 (list s-score s-dv s-dr s-lint s-master)))
         (warn-count   (cl-count "WARN" (list (car s-score) (car s-dv) (car s-dr)
                                              (car s-lint) (car s-master))
                                 :test #'string=))
         (bufname "*Blueprint Pre-Delivery Check*"))
    (with-current-buffer (get-buffer-create bufname)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert "BLUEPRINT PRE-DELIVERY CHECK\n")
      (insert (make-string 44 ?=) "\n\n")
      (insert (format "%-34s %4s  %s\n"
                      (format "Health score (soglia: %d)"
                              blueprint-delivery-score-threshold)
                      (format "%d/100" score)
                      (cdr s-score)))
      (insert (format "%-34s %4d  %s\n"
                      "[DA VALIDARE] residui" da-validare (cdr s-dv)))
      (insert (format "%-34s %4d  %s\n"
                      "[DA REVISIONARE] residui" da-revis (cdr s-dr)))
      (insert (format "%-34s %4d  %s\n"
                      "[FINDING] (solo informativo)" findings
                      blueprint--delivery-info-badge))
      (insert (format "%-34s %4d  %s\n"
                      "Lint warnings" lint-warns (cdr s-lint)))
      (insert (format "%-34s %4s  %s\n"
                      "Master sincronizzato"
                      (if master-ok "sì" "no")
                      (cdr s-master)))
      (insert "\n" (make-string 44 ?-) "\n")
      (if all-ok
          (insert "Risultato: PRONTO PER LA CONSEGNA\n")
        (insert (format "Risultato: %d verifica/he da risolvere prima della consegna\n"
                        warn-count)))
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (switch-to-buffer bufname)))

(provide 'blueprint-delivery)
;;; blueprint-delivery.el ends here
