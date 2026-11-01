;;; blueprint-lint.el --- Linter for Blueprint projects  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Validates Blueprint projects for common issues: missing Arc42
;; headings and dangling dependency references in each component;
;; unresolved markers exceeding thresholds and empty content in every
;; file of the document (master.org and what it includes); includes
;; of missing files.  Output is shown in a compilation-like
;; buffer for navigation.  Supports headless (batch) invocation for CI.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-c4)

(defcustom blueprint-lint-marker-threshold 5
  "Number of unresolved markers before the linter emits a warning."
  :type 'integer
  :group 'blueprint)

(defvar blueprint--lint-expected-headings
  '("Introduction" "Context and Scope" "Constraints" "Solution Strategy"
    "Building Blocks" "Runtime Behavior" "Deployment" "Responsibility"
    "Risks" "Open Questions" "Diagrams")
  "Expected top-level Arc42 headings in a component file.")

(defun blueprint--lint-content (label file)
  "Check the content of FILE, reporting under LABEL.
Returns a list of warning strings: more technical markers (QUESTION,
TBD, FIXME, exported text only, as in the health score) than
`blueprint-lint-marker-threshold', and a file with no content at all."
  (let ((warnings '()))
    (pcase-let ((`(,questions ,tbds ,fixmes) (blueprint--component-metrics file)))
      (let ((total (+ questions tbds fixmes)))
        (when (> total blueprint-lint-marker-threshold)
          (push (format "%s: %d unresolved markers (%d QUESTION, %d TBD, %d FIXME)"
                        label total questions tbds fixmes)
                warnings))))
    ;; Effectively empty content: only headings, keywords, anchors,
    ;; whitespace.  Text in subtrees the export leaves out (the
    ;; templates' :noexport: guides) is not content: every component
    ;; created from a template has some.  A line holding only a
    ;; <<target>> is the anchor the templates put under each heading,
    ;; not content either.
    (with-temp-buffer
      (blueprint--insert-org-file file)
      (goto-char (point-min))
      (let ((content-lines 0)
            (excluded (blueprint--non-exported-subtrees)))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            (unless (or (blueprint--in-regions-p (point) excluded)
                        (string-match-p "^\\s-*$" line)
                        (string-match-p "^\\*+ " line)
                        (string-match-p "^#\\+" line)
                        (string-match-p "^[ \t]*<<[^<>\n]+>>[ \t]*$" line))
              (cl-incf content-lines)))
          (forward-line 1))
        (when (zerop content-lines)
          (push (format "%s: file has no content (only headings, keywords and anchors)"
                        label)
                warnings))))
    (nreverse warnings)))

(defcustom blueprint-lint-lifecycle-checks t
  "When non-nil, the lint also checks the components' life cycle.
Two warnings: an \"active\" component that depends on a \"deprecated\"
one, and an \"active\" component with open FIXMEs.  The checks are
about #+BLUEPRINT_LIFECYCLE:, a different axis from the perimeter
status #+BLUEPRINT_STATUS: (whose in-scope/out-of-scope leak warning
is not affected by this defcustom)."
  :type 'boolean
  :group 'blueprint)

(defun blueprint--lint-component (id file &optional skip-content)
  "Lint component ID at FILE (its arc42.org).  Return a list of warnings.
Checks the expected arc42 headings, the dependencies declared with
#+BLUEPRINT_DEPENDS: and, unless SKIP-CONTENT is non-nil, the content
of FILE (see `blueprint--lint-content').  `blueprint--lint-project'
passes SKIP-CONTENT when arc42.org is not part of the document.  With
`blueprint-lint-lifecycle-checks', also warns for an \"active\"
component with FIXMEs and for an \"active\" component that depends on
a \"deprecated\" one (#+BLUEPRINT_LIFECYCLE:)."
  (if (not (and file (file-exists-p file)))
      (list (format "%s: arc42.org not found" id))
    (let ((warnings '()))
      (with-temp-buffer
        (insert-file-contents file)
        (dolist (heading blueprint--lint-expected-headings)
          (goto-char (point-min))
          (unless (re-search-forward (format "^\\* %s" (regexp-quote heading)) nil t)
            (push (format "%s:%s: missing heading \"%s\""
                          (file-name-nondirectory file) id heading)
                  warnings))))
      (unless skip-content
        (setq warnings (append (reverse (blueprint--lint-content id file))
                               warnings)))
      ;; Life cycle of the component itself (#+BLUEPRINT_LIFECYCLE:).
      (when blueprint-lint-lifecycle-checks
        (let ((fixmes (nth 2 (blueprint--component-metrics file))))
          (when (and (string= (blueprint--component-lifecycle-status id)
                              "active")
                     (> fixmes 0))
            (push (format "%s: active component has %d FIXME(s)" id fixmes)
                  warnings))))
      ;; Check dangling dependencies, in-scope -> out-of-scope leaks and
      ;; active -> deprecated leaks
      (let* ((deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))
             (all-comps (blueprint--components))
             (own-status (blueprint--component-scope-status id))
             (own-lifecycle (blueprint--component-lifecycle-status id)))
        (when deps-str
          (dolist (dep (split-string deps-str))
            (if (not (gethash dep all-comps))
                (push (format "%s: depends on unknown component \"%s\"" id dep)
                      warnings)
              (when (and (string= own-status "in-scope")
                         (string= (blueprint--component-scope-status dep)
                                  "out-of-scope"))
                (push (format
                       "%s: in-scope component depends on out-of-scope component \"%s\""
                       id dep)
                      warnings))
              (when (and blueprint-lint-lifecycle-checks
                         (string= own-lifecycle "active")
                         (string= (blueprint--component-lifecycle-status dep)
                                  "deprecated"))
                (push (format
                       "%s: active component depends on deprecated component \"%s\""
                       id dep)
                      warnings)))))
        (nreverse warnings)))))

(defun blueprint--lint-file-label (file comps root)
  "Return the label of FILE in lint warnings.
\"ID/NAME\" for a document of a component of COMPS, else FILE
relative to ROOT."
  (let ((id (blueprint--component-of-file file comps)))
    (if id
        (format "%s/%s" id (file-name-nondirectory file))
      (file-relative-name file root))))

(defun blueprint--lint-project ()
  "Lint the whole project; return the list of warning strings.
Every component gets the checks of `blueprint--lint-component' on its
arc42.org (headings, dependencies); the content checks of
`blueprint--lint-content' run on every file of the document, that is
master.org and everything it includes (see `blueprint--document-files'),
whether it belongs to a component or not.  An #+INCLUDE: whose file
does not exist is a warning too.  This is the one lint used by
`blueprint-lint', `blueprint-ci-lint', `blueprint-ci-validate' and
`blueprint-pre-delivery-check'."
  (let* ((root (blueprint--root))
         (comps (blueprint--components))
         (docs (blueprint--document-files))
         (warnings '()))
    (dolist (id (sort (hash-table-keys comps) #'string<))
      (let ((file (blueprint--component-file id)))
        (setq warnings
              (append warnings
                      (blueprint--lint-component
                       id file (not (member file docs)))))))
    (dolist (file docs)
      (unless (equal (file-name-nondirectory file) "arc42.org")
        (setq warnings
              (append warnings
                      (blueprint--lint-content
                       (blueprint--lint-file-label file comps root) file)))))
    (dolist (miss (plist-get (blueprint--document-walk) :missing))
      (setq warnings
            (append warnings
                    (list (format "%s: included file \"%s\" not found"
                                  (file-relative-name (cdr miss) root)
                                  (file-relative-name (car miss) root))))))
    warnings))

;;;###autoload
(defun blueprint-lint ()
  "Lint the current Blueprint project, see `blueprint--lint-project'.
Displays warnings in a `*Blueprint Lint*' buffer."
  (interactive)
  (let ((all-warnings (blueprint--lint-project)))
    (if (null all-warnings)
        (message "Blueprint lint: all clear!")
      (with-current-buffer (get-buffer-create "*Blueprint Lint*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Blueprint Lint — %d warning(s)\n\n"
                          (length all-warnings)))
          (dolist (w all-warnings)
            (insert (format "  • %s\n" w))))
        (goto-char (point-min))
        (special-mode)
        (switch-to-buffer (current-buffer))))
    ;; Return non-zero for batch mode
    (when (and noninteractive all-warnings)
      (dolist (w all-warnings)
        (message "LINT: %s" w))
      (kill-emacs 1))))

;;;###autoload
(defun blueprint-lint-component (id)
  "Lint a single component ID.
The checks of `blueprint--lint-component' on arc42.org, then the
content checks on its other documents that are part of the document."
  (interactive
   (list (completing-read "Lint component: "
                          (hash-table-keys (blueprint--components)) nil t)))
  (let* ((file (blueprint--component-file id))
         (included (blueprint--component-included-paths id))
         (warnings
          (append (blueprint--lint-component id file (not (member file included)))
                  (cl-loop for doc in included
                           unless (equal doc file)
                           append (blueprint--lint-content
                                   (format "%s/%s" id (file-name-nondirectory doc))
                                   doc)))))
    (if (null warnings)
        (message "Component %s: all clear!" id)
      (with-current-buffer (get-buffer-create "*Blueprint Lint*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Blueprint Lint — %s — %d warning(s)\n\n"
                          id (length warnings)))
          (dolist (w warnings)
            (insert (format "  • %s\n" w))))
        (goto-char (point-min))
        (special-mode)
        (switch-to-buffer (current-buffer))))))

(provide 'blueprint-lint)
;;; blueprint-lint.el ends here
