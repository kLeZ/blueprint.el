;;; blueprint-lint.el --- Linter for Blueprint projects  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Validates Blueprint components for common issues: missing Arc42
;; headings, unresolved markers exceeding thresholds, dangling dependency
;; references, and empty content.  Output is shown in a compilation-like
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

(defun blueprint--lint-component (id file)
  "Lint component ID at FILE.  Return a list of warning strings."
  (if (not (and file (file-exists-p file)))
      (list (format "%s: arc42.org not found" id))
    (let ((warnings '()))
      (with-temp-buffer
        (insert-file-contents file)
        ;; Check for expected headings
        (dolist (heading blueprint--lint-expected-headings)
          (goto-char (point-min))
          (unless (re-search-forward (format "^\\* %s" (regexp-quote heading)) nil t)
            (push (format "%s:%s: missing heading \"%s\""
                          (file-name-nondirectory file) id heading)
                  warnings)))
        ;; Check marker counts (exported text only, as in the health score)
        (pcase-let ((`(,questions ,tbds ,fixmes)
                     (blueprint--component-metrics file)))
          (let ((total (+ questions tbds fixmes)))
            (when (> total blueprint-lint-marker-threshold)
              (push (format "%s: %d unresolved markers (%d QUESTION, %d TBD, %d FIXME)"
                            id total questions tbds fixmes)
                    warnings))))
        ;; Check for effectively empty content (only headings, keywords,
        ;; anchors, whitespace).  Text in subtrees the export leaves out
        ;; (the templates' :noexport: guides) is not content: every
        ;; component created from a template has some.  A line holding
        ;; only a <<target>> is the anchor the templates put under each
        ;; heading, not content either.
        (let ((org-inhibit-startup t))
          (delay-mode-hooks (org-mode)))
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
            (push (format "%s: file has no content (only headings, keywords and anchors)" id)
                  warnings))))
      ;; Check dangling dependencies, and in-scope -> out-of-scope leaks
      (let* ((deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))
             (all-comps (blueprint--components))
             (own-status (blueprint--component-scope-status id)))
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
                      warnings))))))
      (nreverse warnings))))

;;;###autoload
(defun blueprint-lint ()
  "Lint all components in the current Blueprint project.
Displays warnings in a `*Blueprint Lint*' buffer."
  (interactive)
  (let ((all-warnings '()))
    (maphash
     (lambda (id _dir)
       (let ((file (blueprint--component-file id)))
         (setq all-warnings
               (append all-warnings (blueprint--lint-component id file)))))
     (blueprint--components))
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
  "Lint a single component ID."
  (interactive
   (list (completing-read "Lint component: "
                          (hash-table-keys (blueprint--components)) nil t)))
  (let* ((file (blueprint--component-file id))
         (warnings (blueprint--lint-component id file)))
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
