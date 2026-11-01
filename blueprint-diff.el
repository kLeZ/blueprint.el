;;; blueprint-diff.el --- Semantic component diff for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Shows the git diff of a component's directory with a semantic
;; summary on top: which org headings changed, how the markers moved
;; (QUESTION, ANSWERED, TBD, FIXME added/removed), how many open
;; questions were closed.  The diff itself stays in `diff-mode'.
;; The diff is always requested in plain unified format
;; (--no-ext-diff): a `diff.external' tool in the user's git config
;; (difftastic and friends) would otherwise replace it with a format
;; the summary cannot parse.  Purely read-only: nothing is written to
;; the project.

;;; Code:

(require 'blueprint-core)
(require 'diff-mode)

(defconst blueprint--diff-marker-names '("QUESTION" "ANSWERED" "TBD" "FIXME")
  "Markers counted by `blueprint--diff-summary'.")

(defun blueprint--diff-summary (diff-text)
  "Return the semantic summary of a unified DIFF-TEXT.
A plist with:
  :files     the files touched, as in the diff headers
  :headings  the org headings touched, as (LEVEL TITLE) lists
  :deltas    an alist (MARKER ADDED REMOVED), one per
             `blueprint--diff-marker-names'
  :resolved  the questions the change closed: ANSWERED rows added
             minus ANSWERED rows removed (a QUESTION rewritten as
             ANSWERED is one removed QUESTION and one added ANSWERED;
             an ANSWERED row merely edited is one of each and closes
             nothing), never below 0
Only the lines inside a hunk (after an \"@@\" line) are content: the
file headers (\"--- a/...\", \"+++ b/...\", index, mode lines) are
not, whatever an added or removed content line starts with."
  (let ((files '())
        (headings '())
        (deltas (mapcar (lambda (m) (list m 0 0))
                        blueprint--diff-marker-names))
        (in-hunk nil)
        (case-fold-search nil))
    (dolist (line (split-string diff-text "\n" t))
      (let ((sign nil)
            (body nil))
        (cond
         ((string-match "\\`diff --git a/\\(.*\\) b/\\(.*\\)\\'" line)
          (push (match-string 2 line) files)
          (setq in-hunk nil))
         ((string-prefix-p "@@" line)
          (setq in-hunk t))
         ((not in-hunk) nil)
         ((string-prefix-p "+" line)
          (setq sign 'add body (substring line 1)))
         ((string-prefix-p "-" line)
          (setq sign 'remove body (substring line 1))))
        (when sign
          (when (string-match "\\`\\(\\*+\\)[ \t]+\\(.*\\)\\'" body)
            (push (list (length (match-string 1 body))
                        (match-string 2 body))
                  headings))
          (dolist (d deltas)
            (when (string-match-p (concat "\\<" (car d) "\\>") body)
              (if (eq sign 'add)
                  (cl-incf (nth 1 d))
                (cl-incf (nth 2 d))))))))
    (let ((answered (assoc "ANSWERED" deltas)))
      (list :files (nreverse files)
            :headings (nreverse headings)
            :deltas deltas
            :resolved (max 0 (- (nth 1 answered) (nth 2 answered)))))))

(defun blueprint--diff-summary-text (summary)
  "Return the header lines describing SUMMARY."
  (concat
   (format "File toccati: %s\n"
           (if (plist-get summary :files)
               (mapconcat #'identity (plist-get summary :files) ", ")
             "nessuno"))
   (format "Heading toccati: %s\n"
           (if (plist-get summary :headings)
               (mapconcat (lambda (h)
                            (format "%s %s"
                                    (make-string (car h) ?*) (cadr h)))
                          (plist-get summary :headings)
                          "; ")
             "nessuno"))
   "Marker nel diff:\n"
   (mapconcat (lambda (d)
                (format "  %s: +%d/-%d\n" (car d) (nth 1 d) (nth 2 d)))
              (plist-get summary :deltas)
              "")
   (format "Domande risolte (righe ANSWERED nette aggiunte): %d\n"
           (plist-get summary :resolved))))

(defun blueprint--diff-untracked (rel-dir)
  "Return the diff of the untracked files under REL-DIR, as new files.
A document created and not yet added to git (a new functional.org)
is a change of the component, but `git diff' does not show it: each
untracked file not ignored by git is diffed against /dev/null.  Run
with `default-directory' at the project root."
  (let ((files (with-temp-buffer
                 (when (eq 0 (call-process "git" nil t nil "ls-files" "-z"
                                           "--others" "--exclude-standard"
                                           "--" rel-dir))
                   (split-string (buffer-string) "\0" t)))))
    (mapconcat
     (lambda (file)
       (with-temp-buffer
         ;; --no-index exits 1 when the files differ: that is the
         ;; normal case here, not a failure.
         (call-process "git" nil t nil "diff" "--no-color" "--no-ext-diff"
                       "--no-index" "--" "/dev/null" file)
         (buffer-string)))
     files "")))

(defun blueprint--diff-has-head-p ()
  "Return non-nil when the git repository of `default-directory' has a
commit (HEAD resolves)."
  (eq 0 (ignore-errors
          (call-process "git" nil nil nil
                        "rev-parse" "--verify" "--quiet" "HEAD"))))

;;;###autoload
(defun blueprint-component-diff (&optional component revision)
  "Show the git diff of COMPONENT's directory with a semantic summary.
REVISION, when non-nil and not empty, diffs against it (`git diff
REVISION -- dir').  The default compares the working tree with the
last commit (HEAD), staged changes included: a plain `git diff' would
hide what is already in the index.  In a repository without commits it
falls back to the working tree against the index.  Untracked files of
the component (not ignored by git) are shown as new files.  The buffer holds
the summary and the diff in `diff-mode'.  Signals `user-error' outside
a git repository."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (when current-prefix-arg
           (read-string "Diff against (revision, empty = HEAD): "))))
  (let* ((comps (blueprint--components))
         (dir (gethash component comps))
         (revision (and revision (not (string-empty-p revision)) revision)))
    (unless dir (user-error "Component %s not found" component))
    (let* ((root (blueprint--root))
           (default-directory root)
           (rel-dir (file-relative-name dir root))
           (base (or revision
                     (and (blueprint--diff-has-head-p) "HEAD")))
           (args (append '("diff" "--no-color" "--no-ext-diff")
                         (when base (list base))
                         (list "--" rel-dir)))
           (diff-text (with-temp-buffer
                        (let ((exit (condition-case err
                                        (apply #'call-process
                                               "git" nil t nil args)
                                      (file-missing
                                       (user-error "git not found: %s"
                                                   (error-message-string err))))))
                          (unless (zerop exit)
                            (user-error
                             "git diff failed (exit %d): is the project a git repository?"
                             exit))
                          (concat (buffer-string)
                                  (blueprint--diff-untracked rel-dir)))))
           (summary (blueprint--diff-summary diff-text))
           (buf (get-buffer-create (format "*Blueprint Diff: %s*" component))))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Diff di %s%s\n\n" component
                          (if revision (format " (vs %s)" revision) "")))
          (insert (blueprint--diff-summary-text summary))
          (insert "\n" diff-text))
        (diff-mode)
        (goto-char (point-min)))
      (pop-to-buffer buf)
      buf)))

(defun blueprint-component-diff-at-point ()
  "Diff the component at point in the components list."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (if id
        (blueprint-component-diff id)
      (user-error "No component at point"))))

;; The `d' key of `blueprint-components-mode-map' (blueprint-core.el,
;; which this module requires) diffs the component at point.  Core
;; cannot require this module (the dependency goes the other way), so
;; the binding is installed here, at load time.
(with-eval-after-load 'blueprint-core
  (define-key blueprint-components-mode-map "d"
              #'blueprint-component-diff-at-point))

(provide 'blueprint-diff)
;;; blueprint-diff.el ends here
