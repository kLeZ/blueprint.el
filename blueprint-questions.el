;;; blueprint-questions.el --- Open questions management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; AST-based insertion of open questions into component arc42.org files.
;; Uses `org-element' to find the "Open Questions" heading and insert
;; items without fragile regex manipulation.
;;
;; The extended question format (backward compatible) carries optional
;; metadata on the row itself:
;;
;;   - QUESTION text [TAG: tag]                 (open)
;;   - ANSWERED [YYYY-MM-DD] text [TAG: tag] [FONTE: fonte]
;;
;; Answering rewrites the row's token from QUESTION to ANSWERED, so the
;; question stops counting in the health score, the dashboard and the
;; lint while the history stays in the file.  The list of questions
;; reads every document of each component and filters by tag and state.

;;; Code:

(require 'blueprint-core)
(require 'cl-lib)
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

(defconst blueprint--question-regexp "\\<QUESTION\\>"
  "Regexp of an OPEN question marker, weighted in `blueprint--health-weights'.
The dashboard QUESTION column counts exactly these occurrences, and so
does the open subset of the question list, so the two numbers agree.
ANSWERED rows do not match: they are history, not open points.")

(defconst blueprint--question-any-regexp "\\<\\(?:QUESTION\\|ANSWERED\\)\\>"
  "Regexp of any question row, open (QUESTION) or answered (ANSWERED).
The list of questions scans this: the State column tells them apart.")

;;;###autoload
(defun blueprint-add-question (component question &optional tag)
  "Add QUESTION to COMPONENT's Open Questions section via org-element.
TAG, when non-empty, is recorded on the row as [TAG: tag] -- the
optional metadata of the extended question format; without it the row
is exactly the one older versions wrote, so existing tools and rows
keep working."
  (interactive
   (let ((names (hash-table-keys (blueprint--components))))
     (list (completing-read "Component: " names nil t)
           (read-string "Question: ")
           (read-string "Tag (empty for none): "))))
  (let* ((file (blueprint--component-file component))
         (tag-suffix (if (and tag (not (string-empty-p tag)))
                         (format " [TAG: %s]" tag)
                       "")))
    (unless file (user-error "Component %s not found" component))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let ((pos (blueprint--find-heading "Open Questions"))
              next-heading)
          (if pos
              (progn
                (goto-char pos)
                ;; Find the end of existing content under this heading
                (setq next-heading
                      (save-excursion
                        (when (re-search-forward "^\\* " nil t)
                          (line-beginning-position))))
                (goto-char (or next-heading (point-max)))
                (unless (bolp) (insert "\n"))
                (insert (format "- QUESTION %s%s\n" question tag-suffix))
                ;; Restore the blank line separating this section from
                ;; the next heading, which the insertion above consumed.
                (when (and next-heading (eq (char-after) ?*))
                  (insert "\n")))
            (goto-char (point-max))
            (insert (format "\n* Open Questions\n\n- QUESTION %s%s\n"
                            question tag-suffix))))
        (save-buffer))
      (blueprint--invalidate-cache file))
    (message "Added question to %s" component)))

;;;###autoload
(defun blueprint-answer-question (entry fonte)
  "Answer an open question: rewrite its row as ANSWERED.
ENTRY is a question entry id (COMPONENT FILE LINE), as the list of
questions prompts.  FONTE records the source of the answer, per the
methodology's [FONTE: ...] marking.  The row becomes

  - ANSWERED [YYYY-MM-DD] text [TAG: tag] [FONTE: fonte]

and stops counting in the health score, the dashboard and the lint,
while the history stays in the file."
  (interactive
   (let* ((open (cl-remove-if
                 (lambda (e) (not (string= (aref (cadr e) 3) "open")))
                 (blueprint--question-entries)))
          (choices (mapcar (lambda (e)
                             (cons (format "%s: %s (%s:%d)"
                                           (aref (cadr e) 0)
                                           (aref (cadr e) 1)
                                           (aref (cadr e) 4)
                                           (nth 2 (car e)))
                                   (car e)))
                           open)))
     (when (null choices)
       (user-error "No open question to answer"))
     (list (cdr (assoc (completing-read "Answer question: " choices nil t)
                       choices))
           (read-string "Fonte: "))))
  (pcase-let* ((`(,component ,file ,line) entry)
               (date (format-time-string "%Y-%m-%d")))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (forward-line (1- line))
        (beginning-of-line)
        (unless (looking-at "^-[ \t]*QUESTION[ \t]+\\(.*\\)$")
          (user-error "Line %d of %s is not an open question anymore" line component))
        (let ((text (string-trim (match-string 1))))
          (delete-region (line-beginning-position) (line-end-position))
          (insert (format "- ANSWERED [%s] %s [FONTE: %s]" date text fonte))))
      (save-buffer))
    (blueprint--invalidate-cache file)
    (message "Answered question in %s" component)))

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
    (define-key map "t" #'blueprint-questions-filter-tag)
    (define-key map "s" #'blueprint-questions-filter-state)
    map)
  "Keymap for `blueprint-questions-mode'.")

(define-derived-mode blueprint-questions-mode tabulated-list-mode
  "Blueprint Questions"
  "Major mode for the list of questions of a Blueprint project.
Columns: Component, Question, Tag, State (open or answered) and
Document.  \\[blueprint-questions-filter-tag] filters by tag,
\\[blueprint-questions-filter-state] cycles the state filter."
  (setq tabulated-list-format [("Component" 20 t) ("Question" 50 t)
                               ("Tag" 14 t) ("State" 10 t)
                               ("Document" 20 t)])
  (tabulated-list-init-header))

(defvar blueprint-questions-filter-tag nil
  "Tag filter of the question list.
nil lists every question; a string lists only the questions whose
[TAG: ...] matches it exactly.  Set with
`blueprint-questions-filter-tag' in the list buffer.")

(defvar blueprint-questions-filter-state nil
  "State filter of the question list.
nil or `all' lists open and answered; `open' and `answered' restrict
the list accordingly.  Cycled with
`blueprint-questions-filter-state' in the list buffer.")

(defun blueprint--question-parse (line)
  "Parse one question LINE into (TEXT TAG STATE FONTE).
LINE is the full line of one `blueprint--question-any-regexp'
occurrence.  The metadata tokens ([TAG: ...], [FONTE: ...]) are
stripped from the display text; a QUESTION marker in prose has no
prefix and no metadata, and that is fine."
  (let* ((state (if (string-match-p "\\`-[ \t]*ANSWERED[ \t]" line)
                    "answered" "open"))
         (text line)
         (tag "")
         (fonte ""))
    (when (string-match "\\[TAG:[ \t]*\\([^]]*?\\)[ \t]*]" text)
      (setq tag (match-string 1 text))
      (setq text (replace-match "" t t text)))
    (when (string-match "\\[FONTE:[ \t]*\\([^]]*?\\)[ \t]*]" text)
      (setq fonte (match-string 1 text))
      (setq text (replace-match "" t t text)))
    (setq text (string-trim
                (replace-regexp-in-string
                 "\\`-[ \t]*\\(ANSWERED[ \t]+\\[[0-9-]+\\][ \t]+\\|ANSWERED[ \t]+\\|QUESTION[ \t]+\\)"
                 "" text)))
    (list text tag state fonte)))

(defun blueprint--question-entries ()
  "Return the tabulated-list entries of the questions.
One entry per QUESTION or ANSWERED row in exported text of the
documents of every component that are part of the document
\(`blueprint--component-included-paths'), the same files the dashboard
reads.  The entry id is (COMPONENT FILE LINE) and the fields are
Component, Question, Tag, State and Document."
  (let ((entries '()))
    (dolist (id (sort (hash-table-keys (blueprint--components)) #'string<))
      (dolist (file (blueprint--component-included-paths id))
        (with-temp-buffer
          (blueprint--insert-org-file file)
          ;; Questions in non-exported text (template guides) are
          ;; examples, not questions: `blueprint--marker-positions'
          ;; already leaves those regions out.
          (dolist (pos (blueprint--marker-positions
                        blueprint--question-any-regexp))
            (goto-char pos)
            (pcase-let* ((line (buffer-substring (line-beginning-position)
                                                 (line-end-position)))
                         (`(,text ,tag ,state ,_fonte)
                          (blueprint--question-parse line)))
              (push (list (list id file (line-number-at-pos))
                          (vector id text tag state
                                  (file-name-nondirectory file)))
                    entries))))))
    (nreverse entries)))

(defun blueprint--question-filtered-entries (entries)
  "Filter the question ENTRIES by tag and state.
See `blueprint-questions-filter-tag' and
`blueprint-questions-filter-state'."
  (cl-remove-if-not
   (lambda (e)
     (let ((fields (cadr e)))
       (and (or (null blueprint-questions-filter-tag)
                (string= blueprint-questions-filter-tag (aref fields 2)))
            (or (member blueprint-questions-filter-state '(nil all))
                (string= (aref fields 3)
                         (symbol-name blueprint-questions-filter-state))))))
   entries))

(defun blueprint--question-tags ()
  "Return the distinct tags of the project's questions, sorted."
  (sort (delete-dups
         (delq nil
               (mapcar (lambda (e)
                         (let ((tag (aref (cadr e) 2)))
                           (unless (string-empty-p tag) tag)))
                       (blueprint--question-entries))))
        #'string<))

(defun blueprint--question-filter-line ()
  "Return the mode-line suffix describing the active filters."
  (concat (when blueprint-questions-filter-tag
            (format " [tag: %s]" blueprint-questions-filter-tag))
          (pcase blueprint-questions-filter-state
            ('open " [open]")
            ('answered " [answered]")
            (_ ""))))

(defun blueprint-questions-filter-tag (&optional tag)
  "Filter the question list by TAG.
Called interactively, asks for the tag (empty or \"all\" clears the
filter).  When TAG is non-nil, uses it directly."
  (interactive)
  (let ((choice (or tag
                    (completing-read "Tag (empty = all): "
                                     (cons "all" (blueprint--question-tags))
                                     nil t))))
    (setq blueprint-questions-filter-tag
          (if (member choice '("" "all")) nil choice))
    (blueprint-list-questions)))

(defun blueprint-questions-filter-state ()
  "Cycle the state filter of the question list: all -> open -> answered."
  (interactive)
  (setq blueprint-questions-filter-state
        (pcase blueprint-questions-filter-state
          ((or 'nil 'all) 'open)
          ('open 'answered)
          (_ 'all)))
  (blueprint-list-questions))

;;;###autoload
(defun blueprint-list-questions ()
  "List the questions of the project with tag, state and document.
The rows are the QUESTION and ANSWERED markers of the documents of
each component that master.org includes; the dashboard QUESTION
column counts only the open ones, so the open entries of the list and
the column always agree (without master.org, the documents
`blueprint-sync' would include).  In the list,
\\<blueprint-questions-mode-map>\\[blueprint-questions-visit] opens
the document at the question, \\[blueprint-questions-filter-tag]
filters by tag and \\[blueprint-questions-filter-state] by state."
  (interactive)
  (let* ((entries (blueprint--question-entries))
         (filtered (blueprint--question-filtered-entries entries)))
    (if (and (null entries)
             (null blueprint-questions-filter-tag)
             (member blueprint-questions-filter-state '(nil all)))
        (message "No open questions found.")
      (with-current-buffer (get-buffer-create "*Blueprint Questions*")
        (blueprint-questions-mode)
        (setq tabulated-list-entries filtered)
        (setq mode-line-process (blueprint--question-filter-line))
        (force-mode-line-update)
        (tabulated-list-print)
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-questions)
;;; blueprint-questions.el ends here
