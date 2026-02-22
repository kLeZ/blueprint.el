;;; blueprint-glossary.el --- Glossary management for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Structured glossary stored in .blueprint/glossary.org.  Each term is
;; an Org heading with properties for source attribution.

;;; Code:

(require 'blueprint-core)

(defun blueprint--glossary-file ()
  "Return the path to the glossary file."
  (expand-file-name ".blueprint/glossary.org" (blueprint--root)))

(defun blueprint--ensure-glossary ()
  "Create the glossary file if it does not exist."
  (let ((file (blueprint--glossary-file)))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "#+TITLE: Glossary\n\n")))
    file))

;;;###autoload
(defun blueprint-glossary-add (term definition source)
  "Add TERM with DEFINITION and SOURCE to the project glossary."
  (interactive "sTerm: \nsDefinition: \nsSource: ")
  (let ((file (blueprint--ensure-glossary)))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "* %s\n:PROPERTIES:\n:SOURCE: %s\n:END:\n%s\n"
                      term source definition))
      (save-buffer))
    (message "Added glossary term: %s" term)))

;;;###autoload
(defun blueprint-glossary-list ()
  "Open the project glossary file."
  (interactive)
  (find-file (blueprint--ensure-glossary)))

;;;###autoload
(defun blueprint-glossary-lookup (term)
  "Search for TERM in the glossary and display its definition."
  (interactive "sLookup term: ")
  (let ((file (blueprint--glossary-file)))
    (unless (file-exists-p file)
      (user-error "No glossary file found"))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (if (re-search-forward (format "^\\* %s" (regexp-quote term)) nil t)
          (let ((start (line-beginning-position))
                (end (or (save-excursion
                           (when (re-search-forward "^\\* " nil t)
                             (line-beginning-position)))
                         (point-max))))
            (message "%s" (string-trim
                           (buffer-substring-no-properties start end))))
        (message "Term \"%s\" not found in glossary" term)))))

(provide 'blueprint-glossary)
;;; blueprint-glossary.el ends here
