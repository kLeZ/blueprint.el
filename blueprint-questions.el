;;; blueprint-questions.el --- Open questions management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; AST-based insertion of open questions into component arc42.org files.
;; Uses `org-element' to find the "Open Questions" heading and insert
;; items without fragile regex manipulation.  The list of open
;; questions reads every document of each component.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

(defun blueprint--find-heading (heading)
  "Find the position after HEADING in the current buffer using org-element.
Returns the position where new content should be inserted, or nil."
  (let ((tree (org-element-parse-buffer 'headline))
        (result nil))
    (org-element-map tree 'headline
      (lambda (hl)
        (when (and (= (org-element-property :level hl) 1)
                   (string= (org-element-property :raw-value hl) heading))
          (setq result (org-element-property :contents-begin hl)))))
    result))

;;;###autoload
(defun blueprint-add-question (component question)
  "Add QUESTION to COMPONENT's Open Questions section via org-element."
  (interactive
   (let ((names (hash-table-keys (blueprint--components))))
     (list (completing-read "Component: " names nil t)
           (read-string "Question: "))))
  (let ((file (blueprint--component-file component)))
    (unless file (user-error "Component %s not found" component))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let ((pos (blueprint--find-heading "Open Questions")))
          (if pos
              (progn
                (goto-char pos)
                ;; Find the end of existing content under this heading
                (let ((next-heading
                       (save-excursion
                         (when (re-search-forward "^\\* " nil t)
                           (line-beginning-position)))))
                  (goto-char (or next-heading (point-max)))
                  (unless (bolp) (insert "\n"))
                  (insert (format "- QUESTION %s\n" question))
                  ;; Restore the blank line separating this section from the
                  ;; next heading, which the insertion above just consumed.
                  (when (and next-heading (eq (char-after) ?*))
                    (insert "\n"))))
            (goto-char (point-max))
            (insert (format "\n* Open Questions\n\n- QUESTION %s\n" question)))))
      (save-buffer))
    (message "Added question to %s" component)))

;;;###autoload
(defun blueprint-questions-visit ()
  "Visit the question at point, in the document that holds it."
  (interactive)
  (let ((data (tabulated-list-get-id)))
    (when data
      (find-file (nth 1 data))
      (goto-char (point-min))
      (forward-line (1- (nth 2 data))))))

(defvar blueprint-questions-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'blueprint-questions-visit)
    map)
  "Keymap for `blueprint-questions-mode'.")

(define-derived-mode blueprint-questions-mode tabulated-list-mode
  "Blueprint Questions"
  "Major mode for the list of open questions of a Blueprint project."
  (setq tabulated-list-format [("Component" 20 t) ("Question" 60 t)
                               ("Document" 20 t)])
  (tabulated-list-init-header))

(defun blueprint--question-entries ()
  "Return the tabulated-list entries of the open questions.
One entry per \"- QUESTION\" list item in exported text of every
document of every component (arc42.org, functional.org,
infrastructure.org; see `blueprint--component-document-paths').
The entry id is (COMPONENT FILE LINE)."
  (let ((entries '()))
    (dolist (id (sort (hash-table-keys (blueprint--components)) #'string<))
      (dolist (file (blueprint--component-document-paths id))
        (with-temp-buffer
          (blueprint--insert-org-file file)
          ;; Questions in non-exported text (template guides) are
          ;; examples, not open questions.
          (dolist (pos (blueprint--marker-positions
                        "^-[ \t]*QUESTION[ \t]+\\(.*\\)"))
            (goto-char pos)
            (looking-at "^-[ \t]*QUESTION[ \t]+\\(.*\\)")
            (push (list (list id file (line-number-at-pos))
                        (vector id (match-string 1)
                                (file-name-nondirectory file)))
                  entries)))))
    (nreverse entries)))

;;;###autoload
(defun blueprint-list-questions ()
  "List all open questions across all components.
Questions are collected from every document of each component
\(arc42.org, functional.org, infrastructure.org).  In the list,
\\<blueprint-questions-mode-map>\\[blueprint-questions-visit] opens the document at the question."
  (interactive)
  (let ((entries (blueprint--question-entries)))
    (if (null entries)
        (message "No open questions found.")
      (with-current-buffer (get-buffer-create "*Blueprint Questions*")
        (blueprint-questions-mode)
        (setq tabulated-list-entries entries)
        (tabulated-list-print)
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-questions)
;;; blueprint-questions.el ends here
