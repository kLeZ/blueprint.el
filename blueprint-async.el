;;; blueprint-async.el --- Async operations for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Background processing for long-running operations (export, tangle)
;; using Emacs 29+ threads to avoid blocking the UI.

;;; Code:

(require 'blueprint-core)

(defvar blueprint-export-backend)

(defun blueprint--async-run (name func callback)
  "Run FUNC in a background thread named NAME.
Calls CALLBACK with the result when done."
  (make-thread
   (lambda ()
     (let ((result (funcall func)))
       (run-with-timer 0 nil (lambda () (funcall callback result)))))
   name))

;;;###autoload
(defun blueprint-async-export ()
  "Export the project in the background."
  (interactive)
  (require 'blueprint-export)
  (message "Exporting in background...")
  (let ((file (expand-file-name "master.org" (blueprint--root)))
        (backend blueprint-export-backend))
    (blueprint--async-run
     "blueprint-export"
     (lambda ()
       (with-current-buffer (find-file-noselect file)
         (pcase backend
           ('pdf (org-latex-export-to-pdf))
           ('html (org-html-export-to-html))
           (_ nil))
         backend))
     (lambda (backend)
       (message "Blueprint export (%s) complete" backend)))))

;;;###autoload
(defun blueprint-async-tangle ()
  "Tangle all Org files in the project in the background."
  (interactive)
  (message "Tangling in background...")
  (let ((root (blueprint--root)))
    (blueprint--async-run
     "blueprint-tangle"
     (lambda ()
       (let ((files (directory-files-recursively
                     (expand-file-name ".blueprint" root) "\\.org$")))
         (dolist (f files)
           (with-current-buffer (find-file-noselect f)
             (org-babel-tangle)))
         (length files)))
     (lambda (count)
       (message "Blueprint tangle complete: %d files processed" count)))))

(provide 'blueprint-async)
;;; blueprint-async.el ends here
