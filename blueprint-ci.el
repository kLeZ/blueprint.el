;;; blueprint-ci.el --- CI/headless mode for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Batch-mode entry points for CI pipelines.  Each command prints results
;; to stdout and exits with an appropriate code:
;;   0 = success, 1 = warnings, 2 = errors.
;;
;; Usage:
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-lint
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-validate
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-export

;;; Code:

(require 'blueprint-core)
(require 'blueprint-lint)
(require 'blueprint-health)

(declare-function blueprint-sync "blueprint-sync" ())
(declare-function blueprint-export "blueprint-export" ())

;;;###autoload
(defun blueprint-ci-lint ()
  "Run Blueprint linting in batch mode.
Prints warnings to stdout and exits with code 1 if any are found."
  (let ((all-warnings '()))
    (maphash
     (lambda (id _dir)
       (let ((file (blueprint--component-file id)))
         (setq all-warnings
               (append all-warnings
                       (blueprint--lint-component id file)))))
     (blueprint--components))
    (if (null all-warnings)
        (progn
          (message "Blueprint CI lint: PASS")
          (when noninteractive (kill-emacs 0)))
      (message "Blueprint CI lint: %d warning(s)" (length all-warnings))
      (dolist (w all-warnings)
        (message "  %s" w))
      (when noninteractive (kill-emacs 1)))))

;;;###autoload
(defun blueprint-ci-validate ()
  "Run full validation in batch mode: lint + health check + dependency check.
Exits with code 0 (pass), 1 (warnings), or 2 (errors)."
  (let ((exit-code 0)
        (all-warnings '()))
    ;; Lint
    (maphash
     (lambda (id _dir)
       (let ((file (blueprint--component-file id)))
         (setq all-warnings
               (append all-warnings
                       (blueprint--lint-component id file)))))
     (blueprint--components))
    (when all-warnings
      (setq exit-code 1)
      (message "LINT: %d warning(s)" (length all-warnings))
      (dolist (w all-warnings)
        (message "  %s" w)))
    ;; Health
    (let ((score (blueprint-health-score)))
      (message "HEALTH: score = %d/100" score)
      (when (< score 50)
        (setq exit-code (max exit-code 1))
        (message "  WARNING: health score below 50")))
    ;; Dependency check
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (deps-str (when file
                          (with-temp-buffer
                            (insert-file-contents file)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   "^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)" nil t)
                              (match-string 1)))))
              (all-comps (blueprint--components)))
         (when deps-str
           (dolist (dep (split-string deps-str))
             (unless (gethash dep all-comps)
               (setq exit-code 2)
               (message "ERROR: %s depends on unknown component \"%s\"" id dep))))))
     (blueprint--components))
    ;; Summary
    (message "Blueprint CI validate: %s"
             (pcase exit-code
               (0 "PASS")
               (1 "WARN")
               (2 "FAIL")))
    (when noninteractive (kill-emacs exit-code))))

;;;###autoload
(defun blueprint-ci-export ()
  "Run Blueprint export in batch mode."
  (require 'blueprint-sync)
  (require 'blueprint-export)
  (condition-case err
      (progn
        (blueprint-sync)
        (blueprint-export)
        (message "Blueprint CI export: PASS")
        (when noninteractive (kill-emacs 0)))
    (error
     (message "Blueprint CI export: FAIL — %s" (error-message-string err))
     (when noninteractive (kill-emacs 2)))))

(provide 'blueprint-ci)
;;; blueprint-ci.el ends here
