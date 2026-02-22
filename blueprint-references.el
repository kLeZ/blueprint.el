;;; blueprint-references.el --- Reference tracking for Blueprint  -*- lexical-binding:t; -*-

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Tracks document, interview, and system references in
;; .blueprint/references.org with typed properties.

;;; Code:

(require 'blueprint-core)

(defun blueprint--references-file ()
  "Return the path to the references file."
  (expand-file-name ".blueprint/references.org" (blueprint--root)))

(defun blueprint--ensure-references ()
  "Create the references file if it does not exist."
  (let ((file (blueprint--references-file)))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "#+TITLE: References\n\n")))
    file))

;;;###autoload
(defun blueprint-reference-add (title type notes)
  "Add a reference with TITLE, TYPE, and NOTES.
TYPE should be one of: document, interview, system."
  (interactive
   (list (read-string "Reference title: ")
         (completing-read "Type: " '("document" "interview" "system") nil t)
         (read-string "Notes: ")))
  (let ((file (blueprint--ensure-references))
        (date (format-time-string "%Y-%m-%d")))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "* %s\n:PROPERTIES:\n:TYPE: %s\n:DATE: %s\n:END:\n%s\n"
                      title type date notes))
      (save-buffer))
    (message "Added reference: %s" title)))

;;;###autoload
(defun blueprint-reference-list ()
  "Open the project references file."
  (interactive)
  (find-file (blueprint--ensure-references)))

(provide 'blueprint-references)
;;; blueprint-references.el ends here
