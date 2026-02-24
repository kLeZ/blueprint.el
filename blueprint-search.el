;;; blueprint-search.el --- Project search for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Project-wide search using ripgrep (rg) when available, with fallback
;; to grep -r.  Includes preset queries for common markers.

;;; Code:

(require 'blueprint-core)

(defun blueprint--search-command (pattern)
  "Return a search command string for PATTERN in the Blueprint project."
  (let ((dir (expand-file-name ".blueprint" (blueprint--root))))
    (if (executable-find "rg")
        (format "rg --no-heading --line-number %s %s"
                (shell-quote-argument pattern)
                (shell-quote-argument dir))
      (format "grep -rn %s %s"
              (shell-quote-argument pattern)
              (shell-quote-argument dir)))))

;;;###autoload
(defun blueprint-search (pattern)
  "Search for PATTERN across all Blueprint project files."
  (interactive "sSearch pattern: ")
  (let ((default-directory (blueprint--root)))
    (compilation-start (blueprint--search-command pattern) 'grep-mode)))

;;;###autoload
(defun blueprint-search-questions ()
  "Search for QUESTION markers across the project."
  (interactive)
  (blueprint-search "QUESTION"))

;;;###autoload
(defun blueprint-search-tbd ()
  "Search for TBD markers across the project."
  (interactive)
  (blueprint-search "TBD"))

;;;###autoload
(defun blueprint-search-fixme ()
  "Search for FIXME markers across the project."
  (interactive)
  (blueprint-search "FIXME"))

(provide 'blueprint-search)
;;; blueprint-search.el ends here
