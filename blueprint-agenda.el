;;; blueprint-agenda.el --- org-agenda integration for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Turns the open markers of the document (QUESTION, FIXME by default)
;; into TODO entries of an Org agenda file (.blueprint/agenda.org), so
;; they can be triaged from the standard `org-agenda' with deadlines
;; and scheduled dates.
;;
;; `blueprint-agenda-refresh' regenerates the file; entries are keyed
;; by a stable ID (a hash of origin file, text and occurrence), so a
;; refresh preserves what the user added by hand: DEADLINE,
;; SCHEDULED and the TODO/DONE state.  `blueprint-agenda' refreshes
;; and opens `org-agenda-list' restricted to that file.  The agenda
;; file lives in the data directory and is not included in master.org,
;; so it never enters the counts of the document.

;;; Code:

(require 'blueprint-core)
(require 'cl-lib)
(require 'org-element)

(defcustom blueprint-agenda-marker-types '("QUESTION" "FIXME")
  "Marker types turned into agenda entries by `blueprint-agenda-refresh'.
Each entry is a regexp key of `blueprint--health-weights' without the
regexp decoration (\"QUESTION\", \"FIXME\", \"TBD\", ...)."
  :type '(repeat string)
  :group 'blueprint)

(defcustom blueprint-agenda-add-to-org-agenda nil
  "When non-nil, `blueprint-agenda-refresh' adds the generated agenda
file to `org-agenda-files', so its entries show up in the user's own
agenda.  The file is always visible through `blueprint-agenda',
whatever this value."
  :type 'boolean
  :group 'blueprint)

(defun blueprint--agenda-file ()
  "Return the path of the generated agenda file, in the data directory."
  (blueprint--data-path "agenda.org"))

(defun blueprint--agenda-id (file text occurrence)
  "Return the stable ID of an agenda entry.
FILE, TEXT and OCCURRENCE (the nth same-text marker in FILE) hash to
the same ID however the lines move, so a refresh preserves the
DEADLINE and the state of each entry.  FILE is the path relative to
the project root: an absolute path would change every ID when the
project is moved or cloned elsewhere."
  (substring (md5 (format "%s|%s|%d" file text occurrence)) 0 10))

(defun blueprint--agenda-marker-regexp (type)
  "Return the marker regexp of TYPE (see
`blueprint-agenda-marker-types'), as weighted by
`blueprint--health-weights'."
  (concat "\\<" type "\\>"))

(defun blueprint--agenda-entries (&optional root)
  "Return the agenda entries of the document at ROOT.
A list of plists (:type :component :text :file :line :id), one per
occurrence of every `blueprint-agenda-marker-types' marker in
exported text of the document files, in document order.  Only the
open markers count: the weights leave [FINDING] out (weight 0) by
construction."
  (let* ((root (or root (blueprint--root)))
         (comps (blueprint--components))
         (entries '())
         (seen (make-hash-table :test 'equal)))
    (dolist (file (blueprint--document-files root))
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (dolist (type blueprint-agenda-marker-types)
          (dolist (pos (blueprint--marker-positions
                        (blueprint--agenda-marker-regexp type)))
            (goto-char pos)
            (let* ((line (buffer-substring (line-beginning-position)
                                           (line-end-position)))
                   (text (string-trim
                          (replace-regexp-in-string
                           "\\`-[ \t]*[A-Z]+[ \t]+" "" line)))
                   (key (cons file text))
                   (occurrence (1+ (gethash key seen 0))))
              (puthash key occurrence seen)
              (push (list :type type
                          :component (or (blueprint--component-of-file
                                          file comps)
                                         "progetto")
                          :text text
                          :file file
                          :line (line-number-at-pos)
                          :id (blueprint--agenda-id
                               (file-relative-name file root)
                               text occurrence))
                    entries))))))
    (nreverse entries)))

(defun blueprint--agenda-read-existing (file)
  "Read the user-preserved data of the existing agenda FILE.
A hash: ID → (STATE DEADLINE SCHEDULED), with STATE the TODO keyword
of the entry (\"TODO\" when new) and DEADLINE/SCHEDULED the planning
lines verbatim (nil when absent).  nil when FILE does not exist."
  (when (file-exists-p file)
    (let ((table (make-hash-table :test 'equal)))
      (with-temp-buffer
        ;; org-mode is needed for the TODO/DONE keywords to be parsed
        ;; as such (the :ID property would be found regardless).
        (blueprint--insert-org-file file)
        (org-element-map (org-element-parse-buffer 'headline) 'headline
          (lambda (hl)
            (let ((id (org-element-property :ID hl)))
              (when id
                (puthash id
                         (list (or (org-element-property :todo-keyword hl)
                                   "TODO")
                               (let ((d (org-element-property :deadline hl)))
                                 (and d
                                      (concat "DEADLINE: "
                                              (org-element-timestamp-interpreter
                                               d nil))))
                               (let ((s (org-element-property :scheduled hl)))
                                 (and s
                                      (concat "SCHEDULED: "
                                              (org-element-timestamp-interpreter
                                               s nil)))))
                         table))))))
      table)))

(defun blueprint--agenda-write (entries)
  "Write the agenda file from ENTRIES, preserving user data.
Returns the file path."
  (let* ((file (blueprint--agenda-file))
         (existing (or (blueprint--agenda-read-existing file)
                       (make-hash-table :test 'equal)))
         ;; Links are resolved against the directory of the agenda
         ;; file (the data directory), not against the project root.
         (link-dir (file-name-directory file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert "#+TITLE: Blueprint — punti aperti del documento\n\n"
              "File generato da `blueprint-agenda-refresh': le righe del\n"
              "documento (QUESTION, FIXME...) come TODO per org-agenda.\n"
              "DEADLINE, SCHEDULED e stato vengono preservati al refresh\n"
              "(gli ID sono stabili).  Non e' incluso in master.org.\n\n")
      (dolist (type blueprint-agenda-marker-types)
        (let ((of-type (cl-remove-if-not
                        (lambda (e) (string= (plist-get e :type) type))
                        entries)))
          (when of-type
            (insert (format "* %s\n\n" type))
            (dolist (e of-type)
              (let ((preserved (gethash (plist-get e :id) existing)))
                (insert (format "** %s %s: %s — %s\n"
                                (or (car preserved) "TODO")
                                type
                                (plist-get e :component)
                                (plist-get e :text)))
                (when (cadr preserved) (insert (cadr preserved) "\n"))
                (when (caddr preserved) (insert (caddr preserved) "\n"))
                (insert ":PROPERTIES:\n"
                        (format ":ID: %s\n" (plist-get e :id))
                        (format ":ORIGIN: [[file:%s][%s:%d]]\n"
                                (file-relative-name (plist-get e :file)
                                                    link-dir)
                                (file-name-nondirectory (plist-get e :file))
                                (plist-get e :line))
                        ":BLUEPRINT_MARKER: " type "\n"
                        ":END:\n\n")))))))
    file))

;;;###autoload
(defun blueprint-agenda-refresh ()
  "Regenerate the agenda file from the open markers of the document.
Each marker of `blueprint-agenda-marker-types' becomes a TODO entry
of .blueprint/agenda.org; DEADLINE, SCHEDULED and TODO/DONE state of
the previous entries are preserved across refreshes (stable IDs).
With `blueprint-agenda-add-to-org-agenda' non-nil, the file is also
added to `org-agenda-files'.  Returns the file path."
  (interactive)
  (let ((file (blueprint--agenda-write (blueprint--agenda-entries))))
    (when blueprint-agenda-add-to-org-agenda
      (require 'org-agenda nil t)
      (let ((abs (expand-file-name file)))
        (cond
         ;; A string names a file that lists the agenda files: it is
         ;; the user's to edit, appending to it as a list would turn
         ;; the name into a list of characters.
         ((stringp org-agenda-files)
          (message "org-agenda-files is the file %s: add %s to it by hand"
                   org-agenda-files abs))
         ((not (member abs org-agenda-files))
          (customize-set-variable 'org-agenda-files
                                  (append org-agenda-files (list abs)))))))
    (message "Blueprint agenda written to %s" file)
    file))

;;;###autoload
(defun blueprint-agenda ()
  "Refresh the Blueprint agenda and open it in `org-agenda-list'.
The agenda shows the TODO entries of .blueprint/agenda.org (see
`blueprint-agenda-refresh'); deadlines and scheduled dates set there
work as in any Org agenda."
  (interactive)
  (let ((file (blueprint-agenda-refresh)))
    (require 'org-agenda)
    (let ((org-agenda-files (list (expand-file-name file))))
      (org-agenda-list))))

(provide 'blueprint-agenda)
;;; blueprint-agenda.el ends here
