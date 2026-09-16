;;; blueprint-delivery.el --- Pre-delivery checklist for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; `blueprint-pre-delivery-check' produces a structured report showing
;; whether the current project is ready to be delivered to the client.
;;
;; Checks performed:
;;   - Health score vs. configurable threshold
;;   - Count of [DA VALIDARE] markers across the project
;;   - Count of [DA REVISIONARE] markers across the project
;;   - Count of [FINDING] markers still open
;;   - Lint (structural issues in component files)
;;   - Master file existence and sync marker presence

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-lint)

(defcustom blueprint-delivery-score-threshold 80
  "Minimum health score considered acceptable for delivery.
`blueprint-pre-delivery-check' reports WARN when the score is below this value."
  :type 'integer
  :group 'blueprint)

(defun blueprint--delivery-count-marker (marker)
  "Return the total count of MARKER occurrences across all .org files."
  (let ((count 0))
    (dolist (entry (blueprint--scan-marker-occurrences marker))
      (ignore entry)
      (cl-incf count))
    count))

(defun blueprint--delivery-check-master-sync ()
  "Return t if master.org exists and contains blueprint sync markers."
  (let ((master (expand-file-name "master.org" (blueprint--root))))
    (and (file-exists-p master)
         (with-temp-buffer
           (insert-file-contents master)
           (goto-char (point-min))
           (re-search-forward "@@blueprint-sync-start@@" nil t)))))

(defun blueprint--delivery-collect-lint-warnings ()
  "Return total number of lint warnings across all components."
  (let ((total 0))
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (warnings (blueprint--lint-component id file)))
         (cl-incf total (length warnings))))
     (blueprint--components))
    total))

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
Checks health score, unresolved methodology markers, lint warnings,
and master file synchronisation.  The health score threshold is
controlled by `blueprint-delivery-score-threshold'."
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
         (s-fi         (blueprint--delivery-status findings 0 t))
         (s-lint       (blueprint--delivery-status lint-warns 0 t))
         (s-master     (if master-ok (cons "OK  " "[OK]") (cons "WARN" "[ATTENZIONE]")))
         (all-ok       (cl-every (lambda (s) (string= (car s) "OK  "))
                                 (list s-score s-dv s-dr s-fi s-lint s-master)))
         (warn-count   (cl-count "WARN" (list (car s-score) (car s-dv) (car s-dr)
                                              (car s-fi) (car s-lint) (car s-master))
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
                      "[FINDING] aperti" findings (cdr s-fi)))
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
