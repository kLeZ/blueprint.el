;;; blueprint-daily.el --- Daily workflow command for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; One-key daily triage sequence: dashboard → focus → select component
;; or other part of the document → select document → edit.  Designed for the start of a work session.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-dashboard)

(defun blueprint--daily-candidates ()
  "Return the rows of the document with open points, most penalty first.
A list of (ID . SUMMARY): ID is a component id, or the path relative
to the project root of another file of the document (master.org,
glossary, Parte I and V files...; see `blueprint--document-units');
SUMMARY is as returned by `blueprint--files-health-summary' over the
row's files that master.org includes, weighted as in
`blueprint-health-score'.  A row whose only markers are [FINDING]
\(weight 0) is not a candidate.  Ties are broken by ID."
  (let ((result '()))
    (dolist (unit (blueprint--document-units))
      (let ((summary (blueprint--unit-health-summary unit)))
        (when (> (plist-get summary :penalty) 0)
          (push (cons (plist-get unit :id) summary) result))))
    (sort result
          (lambda (a b)
            (let ((pa (plist-get (cdr a) :penalty))
                  (pb (plist-get (cdr b) :penalty)))
              (if (= pa pb)
                  (string< (car a) (car b))
                (> pa pb)))))))

(defun blueprint--daily-document-label (summary)
  "Return a function labelling a document path with its SUMMARY numbers."
  (lambda (path)
    (let ((doc (assoc path (plist-get summary :documents))))
      (format "(penalty %d)" (if doc (nth 2 doc) 0)))))

(defun blueprint--daily-default-document (summary)
  "Return the path of the document with most penalty points in SUMMARY."
  (car (car (sort (copy-sequence (plist-get summary :documents))
                  (lambda (a b) (> (nth 2 a) (nth 2 b)))))))

;;;###autoload
(defun blueprint-daily ()
  "Start a daily Blueprint work session.
Opens the dashboard in focus mode, prompts to select a component or
another file of the document needing attention, then, for a
component, one of its documents (arc42.org, functional.org,
infrastructure.org), and opens it for editing.  Candidates are
ordered by penalty points summed over their files in master.org,
with the weights of `blueprint-health-score'; the document with most
penalty points is the default."
  (interactive)
  (blueprint--root)  ; ensure we're in a project
  ;; Show dashboard in focus mode
  (setq blueprint-dashboard-focus t)
  (blueprint-dashboard)
  (let ((needs-work (blueprint--daily-candidates)))
    (if (null needs-work)
        (message "No open points in the document! Nothing to triage.")
      (let* ((choices (mapcar
                       (lambda (item)
                         (cons (format "%s (penalty %d, %d open markers)"
                                       (car item)
                                       (plist-get (cdr item) :penalty)
                                       (plist-get (cdr item) :open))
                               item))
                       needs-work))
             (choice (completing-read "Work on: " (mapcar #'car choices)
                                      nil t))
             (item (cdr (assoc choice choices)))
             (summary (cdr item))
             (file (if (gethash (car item) (blueprint--components))
                       (blueprint--read-component-document
                        (car item)
                        (blueprint--daily-default-document summary)
                        (blueprint--daily-document-label summary))
                     (blueprint--document-part-file (car item)))))
        (when file (find-file file))))))

(provide 'blueprint-daily)
;;; blueprint-daily.el ends here
