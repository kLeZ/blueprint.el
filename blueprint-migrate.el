;;; blueprint-migrate.el --- Template migration for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Compares project templates against system defaults (diff) and copies
;; missing template files into the project (non-destructive migration).
;;
;; `blueprint-migrate-directory' renames the project data directory
;; (e.g. the legacy `.blueprint/' to a new `blueprint-directory-name')
;; and rewrites every file link and #+INCLUDE/#+SETUPFILE path in the
;; project's Org files that the rename would otherwise break.

;;; Code:

(require 'blueprint-core)
(require 'org-element)

;;;###autoload
(defun blueprint-template-diff ()
  "Compare project templates against system defaults.
Displays the diff in a `diff-mode' buffer.
Signals an error if the project templates directory does not exist."
  (interactive)
  (let ((proj-dir (blueprint--project-template-dir)))
    (unless (file-directory-p proj-dir)
      (user-error "No project templates directory; run blueprint-template-migrate first"))
    (let ((default-directory (blueprint--root)))
      (compilation-start
       (format "diff -ru %s %s"
               (shell-quote-argument blueprint-template-dir)
               (shell-quote-argument proj-dir))
       'diff-mode))))

;;;###autoload
(defun blueprint-template-migrate ()
  "Copy missing template files from system defaults to the project.
Only adds files that do not already exist in the project templates
directory (non-destructive)."
  (interactive)
  (let ((src blueprint-template-dir)
        (dst (blueprint--project-template-dir)))
    (make-directory dst t)
    (dolist (f (directory-files src t "^[^.]"))
      (let ((target (expand-file-name (file-name-nondirectory f) dst)))
        (unless (file-exists-p target)
          (copy-file f target))))
    (message "Templates migrated (non-destructive)")))

;;; --- Data directory migration ---

(defconst blueprint--migrate-path-keywords '("INCLUDE" "SETUPFILE")
  "Org keywords whose value starts with a file path rewritten on migration.")

(defun blueprint--path-inside-p (path dir)
  "Return non-nil if PATH is DIR itself or lies under DIR (both absolute)."
  (let ((path (directory-file-name path))
        (dir (directory-file-name dir)))
    (or (string= path dir)
        (string-prefix-p (file-name-as-directory dir) path))))

(defun blueprint--migrate-map-file (file from to)
  "Return FILE with its FROM prefix replaced by TO, or FILE if outside FROM."
  (if (blueprint--path-inside-p file from)
      (concat (directory-file-name to)
              (substring (directory-file-name file)
                         (length (directory-file-name from)))
              (if (directory-name-p file) "/" ""))
    file))

(defun blueprint--migrate-rewrite-path (path old-dir new-dir from to)
  "Return the replacement for link PATH, or nil when it needs no change.
PATH appears in a file that lived in OLD-DIR and will live in NEW-DIR
once directory FROM is renamed to TO.  A relative PATH is resolved
against OLD-DIR, mapped through the rename and made relative again to
NEW-DIR, which also fixes links pointing out of the moved tree when its
depth changes.  An absolute PATH is only changed if it points into FROM."
  (let* ((absolute (file-name-absolute-p path))
         (target (expand-file-name path old-dir))
         (mapped (blueprint--migrate-map-file target from to))
         (new (cond (absolute
                     (and (not (string= mapped target)) mapped))
                    ((and (string= mapped target)
                          (string= (file-name-as-directory old-dir)
                                   (file-name-as-directory new-dir)))
                     nil)
                    (t (file-relative-name mapped new-dir)))))
    (and new (not (string= new path)) new)))

(defun blueprint--migrate-keyword-path (value)
  "Return the file path at the start of keyword VALUE, or nil.
Handles a double-quoted or bare path and drops a `::search' suffix."
  (let ((path (cond ((string-match "\\`[ \t]*\"\\([^\"]+\\)\"" value)
                     (match-string 1 value))
                    ((string-match "\\`[ \t]*\\([^ \t\"]+\\)" value)
                     (match-string 1 value)))))
    (when path
      (car (split-string path "::")))))

(defun blueprint--migrate-file-edits (file from to)
  "Return the edits FILE needs when directory FROM is renamed to TO.
Each edit is (BEG END REPLACEMENT) against FILE's current contents,
sorted by descending BEG so they can be applied back to front."
  (let* ((old-dir (file-name-directory file))
         (new-dir (file-name-directory (blueprint--migrate-map-file file from to)))
         (edits '()))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((org-inhibit-startup t))
        (delay-mode-hooks (org-mode)))
      (let ((add-edit
             (lambda (path beg end)
               (let ((new (and path (not (string-empty-p path))
                               (blueprint--migrate-rewrite-path
                                path old-dir new-dir from to))))
                 (when new
                   (save-excursion
                     (goto-char beg)
                     (when (search-forward path end t)
                       (push (list (match-beginning 0) (match-end 0) new)
                             edits))))))))
        (org-element-map (org-element-parse-buffer) '(link keyword)
          (lambda (el)
            (pcase (org-element-type el)
              ('link
               (when (string= (org-element-property :type el) "file")
                 (funcall add-edit (org-element-property :path el)
                          (org-element-property :begin el)
                          (org-element-property :end el))))
              ('keyword
               (when (member (org-element-property :key el)
                             blueprint--migrate-path-keywords)
                 (funcall add-edit
                          (blueprint--migrate-keyword-path
                           (org-element-property :value el))
                          (org-element-property :begin el)
                          (org-element-property :end el)))))))))
    (sort edits (lambda (a b) (> (car a) (car b))))))

(defun blueprint--migrate-org-files (root from)
  "Return every Org file under ROOT, including those under data dir FROM.
Other hidden directories (.git and the like) are skipped."
  (directory-files-recursively
   root blueprint--org-file-regexp nil
   (lambda (dir)
     (or (not (string-prefix-p "." (file-name-nondirectory
                                    (directory-file-name dir))))
         (blueprint--path-inside-p dir from)))))

(defun blueprint--migrate-leftovers (file from-rel edits)
  "Return (FILE LINE TEXT) for mentions of FROM-REL/ in FILE not in EDITS.
These are plain-text references (prose, src block header arguments)
that the migration does not rewrite."
  (let ((re (concat "\\(?:\\`\\|[^[:alnum:]_.-]\\)\\("
                    (regexp-quote (file-name-as-directory from-rel)) "\\)"))
        (found '()))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward re nil t)
        (let ((pos (match-beginning 1)))
          (unless (cl-some (lambda (e) (and (>= pos (nth 0 e)) (< pos (nth 1 e))))
                           edits)
            (push (list file (line-number-at-pos pos)
                        (string-trim (buffer-substring-no-properties
                                      (line-beginning-position)
                                      (line-end-position))))
                  found)))))
    (nreverse found)))

(defun blueprint--migrate-directory-plan (root from to)
  "Return the migration plan for renaming data directory FROM to TO in ROOT.
FROM and TO are absolute.  The plan is a plist with :edits, an alist
of (FILE . EDITS) keyed by each file's current path, and :leftovers,
a list of (FILE LINE TEXT) plain-text mentions left untouched."
  (let ((from-rel (file-relative-name from root))
        (edits '())
        (leftovers '()))
    (dolist (file (blueprint--migrate-org-files root from))
      (let ((file-edits (blueprint--migrate-file-edits file from to)))
        (when file-edits
          (push (cons file file-edits) edits))
        (setq leftovers (append leftovers
                                (blueprint--migrate-leftovers
                                 file from-rel file-edits)))))
    (list :edits (nreverse edits) :leftovers leftovers)))

(defun blueprint--migrate-check (root from to)
  "Signal a `user-error' if data directory FROM cannot be renamed to TO.
ROOT is the project root; FROM and TO are absolute."
  (cond
   ((not (file-directory-p from))
    (user-error "No data directory %s to migrate" from))
   ((string= (directory-file-name from) (directory-file-name to))
    (user-error "Data directory is already %s; nothing to migrate"
                (file-relative-name to root)))
   ((file-exists-p to)
    (user-error "Target %s already exists; move or merge it first" to))
   ((or (blueprint--path-inside-p to from) (blueprint--path-inside-p from to))
    (user-error "Cannot migrate %s to %s: one is inside the other"
                (file-relative-name from root) (file-relative-name to root)))))

(defun blueprint--migrate-check-buffers (from files)
  "Signal a `user-error' if a modified buffer visits a file under FROM or in FILES."
  (dolist (buf (buffer-list))
    (let ((name (buffer-file-name buf)))
      (when (and name (buffer-modified-p buf)
                 (or (blueprint--path-inside-p (expand-file-name name) from)
                     (member (expand-file-name name) files)))
        (user-error "Buffer %s has unsaved changes; save or revert it first"
                    (buffer-name buf))))))

(defun blueprint--migrate-git-tracked-p (root from)
  "Return non-nil if ROOT is a git work tree tracking files under FROM."
  (and (executable-find "git")
       (let ((default-directory root))
         (eq 0 (process-file "git" nil nil nil "ls-files" "--error-unmatch"
                             "--" (file-relative-name from root))))))

(defun blueprint--migrate-rename (root from to)
  "Rename directory FROM to TO in project ROOT.
Uses `git mv' when git tracks FROM, so history follows the files.
Returns the symbol `git' or `file' depending on the method used."
  (make-directory (file-name-directory (directory-file-name to)) t)
  (if (blueprint--migrate-git-tracked-p root from)
      (let ((default-directory root))
        (with-temp-buffer
          (unless (eq 0 (process-file "git" nil t nil "mv" "--"
                                      (file-relative-name from root)
                                      (file-relative-name to root)))
            (user-error "Command git mv failed: %s" (string-trim (buffer-string)))))
        'git)
    (rename-file (directory-file-name from) (directory-file-name to))
    'file))

(defun blueprint--migrate-apply-edits (file edits)
  "Apply EDITS (from `blueprint--migrate-file-edits') to FILE on disk."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((coding last-coding-system-used))
      (dolist (e edits)
        (goto-char (nth 0 e))
        (delete-region (nth 0 e) (nth 1 e))
        (insert (nth 2 e)))
      (let ((coding-system-for-write coding))
        (write-region nil nil file nil 'silent)))))

(defun blueprint--migrate-update-buffers (from to edited)
  "Point buffers under FROM at TO and revert those visiting EDITED files.
EDITED lists the new paths of files rewritten by the migration."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (let ((name (and buffer-file-name (expand-file-name buffer-file-name))))
        (when (and name (blueprint--path-inside-p name from))
          (set-visited-file-name (blueprint--migrate-map-file name from to) t t)
          (setq name (expand-file-name buffer-file-name)))
        (when (and default-directory
                   (blueprint--path-inside-p (expand-file-name default-directory) from))
          (setq default-directory
                (file-name-as-directory
                 (blueprint--migrate-map-file
                  (expand-file-name default-directory) from to))))
        (when (and name (member name edited))
          (revert-buffer t t t))))))

(defun blueprint--migrate-report (root from to method plan)
  "Show the outcome of a data directory migration from FROM to TO in ROOT.
METHOD is the rename method, PLAN the plan that was applied."
  (with-current-buffer (get-buffer-create "*Blueprint Migrate*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Data directory: %s -> %s (%s)\n\n"
                      (file-relative-name from root) (file-relative-name to root)
                      (if (eq method 'git) "git mv" "rename")))
      (insert "Rewritten paths:\n")
      (if (plist-get plan :edits)
          (dolist (entry (plist-get plan :edits))
            (insert (format "  %s: %d\n"
                            (file-relative-name
                             (blueprint--migrate-map-file (car entry) from to) root)
                            (length (cdr entry)))))
        (insert "  none\n"))
      (insert "\nPlain-text mentions left untouched (check by hand):\n")
      (if (plist-get plan :leftovers)
          (dolist (l (plist-get plan :leftovers))
            (insert (format "  %s:%d: %s\n"
                            (file-relative-name
                             (blueprint--migrate-map-file (nth 0 l) from to) root)
                            (nth 1 l) (nth 2 l))))
        (insert "  none\n"))
      (goto-char (point-min))
      (special-mode))
    (current-buffer)))

;;;###autoload
(defun blueprint-migrate-directory (&optional target no-confirm)
  "Rename the project data directory to TARGET and fix the paths into it.
TARGET is relative to the project root and defaults to
`blueprint-directory-name'; the source is the directory currently in
use (see `blueprint--data-dir').  Every file link and #+INCLUDE or
#+SETUPFILE path in the project's Org files that the rename would
break is rewritten, including links from files inside the moved tree
to files outside it.  The rename uses `git mv' when git tracks the
directory.  Plain-text mentions (prose, src block arguments) are only
listed in the report buffer.

Nothing is touched until the plan is confirmed, unless NO-CONFIRM is
non-nil.  When TARGET differs from both `blueprint-directory-name'
and the legacy \".blueprint\", set that variable afterwards:
otherwise `blueprint--root' no longer finds the project."
  (interactive
   (list (read-string (format "Rename data directory to (default %s): "
                              (blueprint--directory-name))
                      nil nil (blueprint--directory-name))))
  (let* ((target (or target (blueprint--directory-name)))
         (root (expand-file-name (blueprint--root)))
         (from (directory-file-name (blueprint--data-dir root)))
         (to nil))
    (unless (blueprint--valid-directory-name-p target)
      (user-error "Invalid target %S: must be a relative path inside the project"
                  target))
    (setq to (directory-file-name (expand-file-name target root)))
    (blueprint--migrate-check root from to)
    (let* ((plan (blueprint--migrate-directory-plan root from to))
           (edited-old (mapcar #'car (plist-get plan :edits))))
      (blueprint--migrate-check-buffers from edited-old)
      (when (or no-confirm
                (yes-or-no-p
                 (format "Rename %s/ to %s/ and rewrite %d path(s) in %d file(s)? "
                         (file-relative-name from root) target
                         (apply #'+ (mapcar (lambda (e) (length (cdr e)))
                                            (plist-get plan :edits)))
                         (length edited-old))))
        (let ((method (blueprint--migrate-rename root from to))
              (edited-new '()))
          (dolist (entry (plist-get plan :edits))
            (let ((new-file (blueprint--migrate-map-file (car entry) from to)))
              (blueprint--migrate-apply-edits new-file (cdr entry))
              (push new-file edited-new)))
          (blueprint--migrate-update-buffers from to edited-new)
          (blueprint--invalidate-cache)
          (remhash root blueprint--warned-roots)
          (let ((report (blueprint--migrate-report root from to method plan)))
            (unless no-confirm
              (display-buffer report)))
          (unless (member (directory-file-name target)
                          (list (blueprint--directory-name)
                                blueprint--legacy-directory-name))
            (display-warning
             'blueprint
             (format "Data directory is now %s/, but `blueprint-directory-name' is %S: set it to %S, or the project will not be found"
                     target blueprint-directory-name target)))
          (message "Blueprint data directory migrated to %s/" target)
          plan)))))

(provide 'blueprint-migrate)
;;; blueprint-migrate.el ends here
