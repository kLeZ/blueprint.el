;;; blueprint-risks.el --- Rule-based risk suggestions for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Deterministic pattern matching against the text of the document
;; (each component's documents in master.org, and the other files
;; master.org includes) to suggest common architectural risks.  Provides an interactive command to
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

(defun blueprint--risk-pattern-matches (files)
  "Return the rules of `blueprint-risk-rules' that match in FILES.
A list of plists (:risk :severity :match :file), one per rule that
matches somewhere, with its first match.  Rules match case-
insensitively and only in exported text, as markers do (see
`blueprint--uncounted-regions'): the templates' :noexport: guides and
example blocks are not the component's text."
  (let ((found '()))
    (dolist (rule blueprint-risk-rules)
      (catch 'matched
        (dolist (file files)
          (when (and file (file-exists-p file))
            (with-temp-buffer
              (blueprint--insert-org-file file)
              (let ((regions (blueprint--uncounted-regions))
                    (case-fold-search t))
                (goto-char (point-min))
                (while (re-search-forward (plist-get rule :pattern) nil t)
                  (unless (blueprint--in-regions-p (match-beginning 0) regions)
                    (push (list :risk (plist-get rule :risk)
                                :severity (plist-get rule :severity)
                                :match (match-string 0)
                                :file file)
                          found)
                    (throw 'matched t)))))))))
    (nreverse found)))

(defun blueprint--risk-immature-p (files)
  "Return non-nil if FILES hold more than 8 technical markers in all.
QUESTION, TBD and FIXME in exported text, through the cached
`blueprint--component-metrics'."
  (> (cl-loop for file in files
              sum (apply #'+ (blueprint--cached-metrics
                              file #'blueprint--component-metrics)))
     8))

(defconst blueprint--risk-immature
  (list :risk "Immature documentation (many unresolved markers)"
        :severity "high"
        :match "structural")
  "Risk reported by `blueprint--risk-immature-p'.")

(defun blueprint--detect-risks (file &optional files)
  "Detect risks of the component whose arc42.org is FILE.
Returns a list of plists (:risk :severity :match).  Patterns of
`blueprint-risk-rules' and the immature-documentation check read
FILES; by default, when FILE belongs to a component, its documents
that are part of the document (see
`blueprint--component-included-paths'), otherwise FILE alone.  The
isolated-component check reads the #+BLUEPRINT_DEPENDS: of all
components."
  (let* ((comps (blueprint--components))
         (id (when file
               (blueprint--component-of-file (expand-file-name file) comps)))
         (files (or files
                    (if id
                        (blueprint--component-included-paths id)
                      (and file (list file)))))
         (findings (reverse (blueprint--risk-pattern-matches files))))
    ;; Structural checks (no pattern matching needed)
    (let ((deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))
          (is-depended nil))
      ;; Check if anyone depends on this component
      (when id
        (maphash
         (lambda (other-id _dir)
           (let* ((other-file (blueprint--component-file other-id))
                  (other-deps (blueprint--org-keyword
                               other-file "BLUEPRINT_DEPENDS")))
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
      (when (blueprint--risk-immature-p files)
        (push blueprint--risk-immature findings)))
    (nreverse findings)))

(defun blueprint--detect-part-risks (file)
  "Detect risks in FILE, a file of the document outside the components.
Pattern rules and the immature-documentation check, as in
`blueprint--detect-risks'; no structural check on dependencies."
  (let ((findings (blueprint--risk-pattern-matches (list file))))
    (if (blueprint--risk-immature-p (list file))
        (append findings (list blueprint--risk-immature))
      findings)))

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
  "Analyze the whole document and suggest architectural risks.
Every component (its documents in master.org, see
`blueprint--detect-risks'), then every other file of the document
\(see `blueprint--detect-part-risks')."
  (interactive)
  (let ((all-risks '()))
    (dolist (unit (blueprint--document-units))
      (let* ((id (plist-get unit :id))
             (risks (if (eq (plist-get unit :kind) 'component)
                        (blueprint--detect-risks (blueprint--component-file id))
                      (blueprint--detect-part-risks (car (plist-get unit :files))))))
        (when risks
          (push (cons id risks) all-risks))))
    (setq all-risks (nreverse all-risks))
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
