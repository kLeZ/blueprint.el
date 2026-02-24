;;; blueprint-daily.el --- Daily workflow command for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; One-key daily triage sequence: dashboard → focus → select component →
;; edit.  Designed for the start of a work session.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-dashboard)

;;;###autoload
(defun blueprint-daily ()
  "Start a daily Blueprint work session.
Opens the dashboard in focus mode, prompts to select a component
needing attention, and opens it for editing."
  (interactive)
  (blueprint--root)  ; ensure we're in a project
  ;; Show dashboard in focus mode
  (setq blueprint-dashboard-focus t)
  (blueprint-dashboard)
  ;; Prompt for component selection
  (let* ((comps (blueprint--components))
         (needs-work '()))
    ;; Find components that need attention
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (metrics (blueprint--cached-metrics
                        file #'blueprint--component-metrics))
              (total (apply #'+ metrics)))
         (when (> total 0)
           (push (cons id total) needs-work))))
     comps)
    (if (null needs-work)
        (message "All components are clean! Nothing to triage.")
      ;; Sort by number of issues (most first)
      (setq needs-work (sort needs-work (lambda (a b) (> (cdr a) (cdr b)))))
      (let* ((choices (mapcar (lambda (item)
                                (format "%s (%d markers)" (car item) (cdr item)))
                              needs-work))
             (choice (completing-read "Work on: " choices nil t))
             (name (car (split-string choice " "))))
        (find-file (blueprint--component-file name))))))

(provide 'blueprint-daily)
;;; blueprint-daily.el ends here
