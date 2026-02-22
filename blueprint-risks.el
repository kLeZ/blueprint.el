;;; blueprint-risks.el --- Rule-based risk suggestions for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Deterministic pattern matching against component text to suggest
;; common architectural risks.  Provides an interactive command to
;; review suggestions and optionally insert them into the Risks section.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)

(defvar blueprint-risk-rules
  '((:pattern "single point of failure\\|SPOF\\|single-point"
     :risk "Single point of failure detected"
     :severity "high")
    (:pattern "no owner\\|owner unknown\\|ownership unclear"
     :risk "Unclear ownership"
     :severity "medium")
    (:pattern "no monitoring\\|unmonitored\\|without monitoring"
     :risk "Missing monitoring"
     :severity "medium")
    (:pattern "no backup\\|without backup\\|unbackupped"
     :risk "No backup strategy"
     :severity "high")
    (:pattern "no test\\|untested\\|without tests\\|not tested"
     :risk "Missing test coverage"
     :severity "medium")
    (:pattern "manual deploy\\|manual process\\|manually"
     :risk "Manual processes present"
     :severity "low")
    (:pattern "deprecated\\|end.of.life\\|EOL\\|legacy"
     :risk "Deprecated or legacy technology"
     :severity "medium")
    (:pattern "hardcoded\\|hard.coded\\|magic number"
     :risk "Hardcoded values or magic numbers"
     :severity "low"))
  "List of risk detection rules.
Each rule is a plist with :pattern (regexp), :risk (description),
and :severity (high/medium/low).")

(defun blueprint--detect-risks (file)
  "Detect risks in FILE based on `blueprint-risk-rules'.
Returns a list of plists (:risk :severity :match)."
  (let ((findings '()))
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (dolist (rule blueprint-risk-rules)
          (goto-char (point-min))
          (when (re-search-forward (plist-get rule :pattern) nil t)
            (push (list :risk (plist-get rule :risk)
                        :severity (plist-get rule :severity)
                        :match (match-string 0))
                  findings)))))
    ;; Structural checks (no pattern matching needed)
    (let* ((comps (blueprint--components))
           (id (when file
                 (let ((dir (file-name-directory file)))
                   (file-name-nondirectory (directory-file-name dir)))))
           (deps-str (when file
                       (with-temp-buffer
                         (insert-file-contents file)
                         (goto-char (point-min))
                         (when (re-search-forward
                                "^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)" nil t)
                           (match-string 1)))))
           (is-depended nil))
      ;; Check if anyone depends on this component
      (when id
        (maphash
         (lambda (other-id _dir)
           (let* ((other-file (blueprint--component-file other-id))
                  (other-deps (when other-file
                                (with-temp-buffer
                                  (insert-file-contents other-file)
                                  (goto-char (point-min))
                                  (when (re-search-forward
                                         "^#\\+BLUEPRINT_DEPENDS:\\s-*\\(.*\\S-\\)" nil t)
                                    (match-string 1))))))
             (when (and other-deps
                        (member id (split-string other-deps)))
               (setq is-depended t))))
         comps)
        ;; Isolated component check
        (when (and (or (null deps-str) (string-blank-p (or deps-str "")))
                   (not is-depended))
          (push (list :risk "Isolated component (no dependencies in or out)"
                      :severity "low"
                      :match "structural")
                findings)))
      ;; Immature documentation check
      (let ((metrics (blueprint--cached-metrics
                      file #'blueprint--component-metrics)))
        (when (> (apply #'+ metrics) 8)
          (push (list :risk "Immature documentation (many unresolved markers)"
                      :severity "high"
                      :match "structural")
                findings))))
    (nreverse findings)))

;;;###autoload
(defun blueprint-suggest-risks (component)
  "Analyze COMPONENT and suggest architectural risks."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)))
  (let* ((file (blueprint--component-file component))
         (risks (blueprint--detect-risks file)))
    (if (null risks)
        (message "No risks detected for %s" component)
      (with-current-buffer (get-buffer-create "*Blueprint Risks*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Risk suggestions for: %s\n\n" component))
          (dolist (r risks)
            (insert (format "  [%s] %s (matched: %s)\n"
                            (upcase (plist-get r :severity))
                            (plist-get r :risk)
                            (plist-get r :match)))))
        (goto-char (point-min))
        (special-mode)
        (switch-to-buffer (current-buffer))))))

;;;###autoload
(defun blueprint-suggest-risks-all ()
  "Analyze all components and suggest architectural risks."
  (interactive)
  (let ((all-risks '()))
    (maphash
     (lambda (id _dir)
       (let ((risks (blueprint--detect-risks (blueprint--component-file id))))
         (when risks
           (push (cons id risks) all-risks))))
     (blueprint--components))
    (if (null all-risks)
        (message "No risks detected across the project")
      (with-current-buffer (get-buffer-create "*Blueprint Risks*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Blueprint Risk Report\n\n")
          (dolist (entry all-risks)
            (insert (format "── %s ──\n" (car entry)))
            (dolist (r (cdr entry))
              (insert (format "  [%s] %s\n"
                              (upcase (plist-get r :severity))
                              (plist-get r :risk))))
            (insert "\n")))
        (goto-char (point-min))
        (special-mode)
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-risks)
;;; blueprint-risks.el ends here
