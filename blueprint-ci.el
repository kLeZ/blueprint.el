;;; blueprint-ci.el --- CI/headless mode for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Batch-mode entry points for CI pipelines.  Each command prints results
;; to stdout and exits with an appropriate code:
;;   0 = success, 1 = warnings, 2 = errors.
;;
;; Usage:
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-lint
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-validate
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-export
;;   Emacs -Q --batch -l blueprint.el -f blueprint-ci-check-odt-styles

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-lint)
(require 'blueprint-health)
(require 'blueprint-upgrade)

(declare-function blueprint-sync "blueprint-sync" ())
(declare-function blueprint-export "blueprint-export" ())
(declare-function blueprint--check-odt-styles-missing "blueprint-export" ())
(declare-function blueprint--graph-deps "blueprint-graph" ())

;;;###autoload
(defun blueprint-ci-lint ()
  "Run Blueprint linting in batch mode.
Lints the components and every file of the document (see
`blueprint--lint-project').  Prints warnings to stdout and exits with
code 1 if any are found."
  (let ((all-warnings (blueprint--lint-project)))
    (if (null all-warnings)
        (progn
          (message "Blueprint CI lint: PASS")
          (when noninteractive (kill-emacs 0)))
      (message "Blueprint CI lint: %d warning(s)" (length all-warnings))
      (dolist (w all-warnings)
        (message "  %s" w))
      (when noninteractive (kill-emacs 1)))))

(defcustom blueprint-ci-pending-migrations 'ignore
  "Effect of the optional migrations available on `blueprint-ci-validate'.
`ignore' only reports them (the default: Blueprint reads the old
formats, a pending migration is not a defect), `warn' makes the run a
warning (exit 1), `error' a failure (exit 2).  See
`blueprint-project-upgrade'."
  :type '(choice (const :tag "Report only" ignore)
                 (const :tag "Warning (exit 1)" warn)
                 (const :tag "Failure (exit 2)" error))
  :group 'blueprint)

;;;###autoload
(defun blueprint-ci-validate ()
  "Run full validation in batch mode: lint + health check + dependency check.
Lint and health score cover the whole document, master.org and the
files it includes (see `blueprint--lint-project' and
`blueprint-health-score').  The project version and the optional
migrations available are reported; they change the exit code only as
`blueprint-ci-pending-migrations' says.  Exits with code 0 (pass), 1
\(warnings), or 2 (errors)."
  (let ((exit-code 0)
        (all-warnings (blueprint--lint-project)))
    ;; Lint
    (when all-warnings
      (setq exit-code 1)
      (message "LINT: %d warning(s)" (length all-warnings))
      (dolist (w all-warnings)
        (message "  %s" w)))
    ;; Health
    (let ((score (blueprint-health-score)))
      (message "HEALTH: score = %d/100" score)
      (when (< score 50)
        (setq exit-code (max exit-code 1))
        (message "  WARNING: health score below 50")))
    ;; Dependency check
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))
              (all-comps (blueprint--components)))
         (when deps-str
           (dolist (dep (split-string deps-str))
             (unless (gethash dep all-comps)
               (setq exit-code 2)
               (message "ERROR: %s depends on unknown component \"%s\"" id dep))))))
     (blueprint--components))
    ;; Project version and optional migrations
    (let ((u (blueprint--upgrade-summary)))
      (when u
        (message "VERSION: project %s (%s), package %s"
                 (plist-get u :version) (plist-get u :source) (plist-get u :package))
        (when (plist-get u :pending)
          (message "  MIGRATIONS available (blueprint-project-upgrade): %s"
                   (mapconcat #'identity (plist-get u :pending) " "))
          (pcase blueprint-ci-pending-migrations
            ('warn (setq exit-code (max exit-code 1)))
            ('error (setq exit-code 2))))))
    ;; Summary
    (message "Blueprint CI validate: %s"
             (pcase exit-code
               (0 "PASS")
               (1 "WARN")
               (2 "FAIL")))
    (when noninteractive (kill-emacs exit-code))))

;;;###autoload
(defun blueprint-ci-export ()
  "Run Blueprint export in batch mode."
  (require 'blueprint-sync)
  (require 'blueprint-export)
  (condition-case err
      (progn
        (blueprint-sync)
        (blueprint-export)
        (message "Blueprint CI export: PASS")
        (when noninteractive (kill-emacs 0)))
    (error
     (message "Blueprint CI export: FAIL — %s" (error-message-string err))
     (when noninteractive (kill-emacs 2)))))

;;;###autoload
(defun blueprint-ci-check-odt-styles ()
  "Run `blueprint--check-odt-styles-missing' in batch mode.
Opt-in, unlike `blueprint-ci-validate': it requires an actual ODT
export and a #+ODT_STYLES_FILE:, so most CI pipelines have no reason
to run it on every push -- add it to your own workflow only if
master.org sets a corporate ODT_STYLES_FILE.  Exits 0 (no missing
styles) or 2 (missing styles found)."
  (require 'blueprint-export)
  (condition-case err
      (let* ((result (blueprint--check-odt-styles-missing))
             (missing (car result)))
        (if (null missing)
            (progn
              (message "Blueprint CI check-odt-styles: PASS")
              (when noninteractive (kill-emacs 0)))
          (message "Blueprint CI check-odt-styles: %d missing style(s)"
                   (length missing))
          (dolist (s missing)
            (message "  %s" s))
          (when noninteractive (kill-emacs 2))))
    (error
     (message "Blueprint CI check-odt-styles: FAIL — %s" (error-message-string err))
     (when noninteractive (kill-emacs 2)))))

;;; --- JSON report for external CI tooling ---

(defcustom blueprint-ci-report-file "blueprint-report.json"
  "Name of the JSON report written by `blueprint-ci-export-json',
relative to the project root."
  :type 'string
  :group 'blueprint)

(defun blueprint--ci-report--table (&rest pairs)
  "Return a hash table of the PAIRS, each (SYMBOL-OR-STRING . VALUE).
`json-serialize' takes hash tables with string keys directly, and a
hash tree is unambiguous where an alist value that is a list is not
\(\(a . (\"x\")) reads back as the flat list (a \"x\")\)."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (pair pairs)
      (puthash (if (symbolp (car pair)) (symbol-name (car pair)) (car pair))
               (cdr pair) table))
    table))

(defconst blueprint--ci-report-marker-names
  `((,blueprint--to-validate-regexp . "to-validate")
    (,blueprint--to-review-regexp . "to-review"))
  "JSON keys of the markers whose regexp is not a plain name.
The English and the legacy Italian form of a marker count together,
under the English name (ADR-003).")

(defun blueprint--ci-report--marker-name (regexp)
  "Turn a marker REGEXP of `blueprint--health-weights' into a JSON key.
The name of `blueprint--ci-report-marker-names' when it has one.
Otherwise \"\\\\<QUESTION\\\\>\" becomes \"question\" and
\"\\\\[FINDING\\\\]\" becomes \"finding\": the markers are
delimited by the two-character escapes \\\\< / \\\\> and \\\\[ / \\\\],
so the name between them is enough and the report keys stay stable
wherever the weights are reordered."
  (or (cdr (assoc regexp blueprint--ci-report-marker-names))
      (let ((name (if (and (> (length regexp) 4)
                       (member (substring regexp 0 2) '("\\<" "\\[")))
                  (substring regexp 2 -2)
                    regexp)))
        (downcase (replace-regexp-in-string "[ \t]+" "-" name)))))

(defun blueprint--ci-report--marker-table (counts)
  "Return the marker COUNTS as a hash table keyed by marker name.
COUNTS is aligned with `blueprint--health-weights'."
  (let ((table (make-hash-table :test 'equal))
        (weights blueprint--health-weights))
    (while (and weights counts)
      (puthash (blueprint--ci-report--marker-name (caar weights))
               (car counts) table)
      (setq weights (cdr weights) counts (cdr counts)))
    table))

(defun blueprint--ci-report-object (&optional root)
  "Return the report object of `blueprint-ci-export-json' for ROOT.
A pure tree of hash tables (string keys), vectors and scalars, taken
by `json-serialize' as it is: no files are written, nothing printed.
The counts follow the same principles as the dashboard: only the
document (master.org and what it includes) and only exported text.
Top-level keys: generated-at, project, health, document-files,
components, dependencies, lint-warnings, blueprint (package and
project version, pending migrations, stale and customized templates);
component keys: id, scope, lifecycle, owner, tech, depends, included,
documents, score, penalty, words, markers."
  (let* ((root (or root (blueprint--root)))
         (summary (blueprint--document-health-summary))
         (comps (blueprint--components))
         (components
          (mapcar
           (lambda (id)
             (let* ((file (blueprint--component-file id))
                    (s (blueprint--component-health-summary id))
                    (deps (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
               (blueprint--ci-report--table
                `(id . ,id)
                `(scope . ,(blueprint--component-scope-status id))
                `(lifecycle . ,(blueprint--component-lifecycle-status id))
                ;; `json-serialize' writes nil as {}: absent keywords
                ;; are JSON null and booleans JSON false explicitly.
                `(owner . ,(or (blueprint--org-keyword file "BLUEPRINT_OWNER")
                               :null))
                `(tech . ,(or (blueprint--org-keyword file "BLUEPRINT_TECH")
                              :null))
                `(depends . ,(if deps (vconcat (split-string deps)) []))
                `(included . ,(if (plist-get s :documents) t :false))
                `(documents
                  . ,(vconcat (mapcar (lambda (doc)
                                        (file-relative-name (car doc) root))
                                      (plist-get s :documents))))
                `(score . ,(plist-get s :score))
                `(penalty . ,(plist-get s :penalty))
                `(words . ,(plist-get s :words))
                `(markers . ,(blueprint--ci-report--marker-table
                              (plist-get s :counts))))))
           (sort (hash-table-keys comps) #'string<)))
         (dependencies
          (when (progn (require 'blueprint-graph nil t)
                       (fboundp 'blueprint--graph-deps))
            (apply #'append
                   (mapcar
                    (lambda (entry)
                      (mapcar (lambda (dep)
                                (blueprint--ci-report--table
                                 `(from . ,(car entry)) `(to . ,dep)))
                              (cdr entry)))
                    (blueprint--graph-deps))))))
    (blueprint--ci-report--table
     `(generated-at . ,(format-time-string "%Y-%m-%dT%H:%M:%S%z"))
     `(project . ,(file-name-nondirectory (directory-file-name root)))
     `(health . ,(blueprint--ci-report--table
                  `(score . ,(plist-get summary :score))
                  `(penalty . ,(plist-get summary :penalty))
                  `(words . ,(plist-get summary :words))
                  `(markers . ,(blueprint--ci-report--marker-table
                                (plist-get summary :counts)))))
     `(document-files
       . ,(vconcat (mapcar (lambda (f) (file-relative-name f root))
                           (blueprint--document-files root))))
     `(components . ,(vconcat components))
     `(dependencies . ,(vconcat (or dependencies nil)))
     `(lint-warnings . ,(vconcat (blueprint--lint-project)))
     `(blueprint
       . ,(let ((u (blueprint--upgrade-summary root)))
            (blueprint--ci-report--table
             `(package-version . ,(or (plist-get u :package) :null))
             `(project-version . ,(or (plist-get u :version) :null))
             `(version-source . ,(if u (symbol-name (plist-get u :source)) :null))
             `(pending-migrations . ,(vconcat (plist-get u :pending)))
             `(stale-templates . ,(or (plist-get u :templates) 0))
             `(customized-templates . ,(or (plist-get u :customized) 0))))))))

;;;###autoload
(defun blueprint-ci-export-json ()
  "Write a JSON report about the project and return the file path.
The report goes to `blueprint-ci-report-file' at the project root and
holds the health score of the document, per-component marker counts,
scores, scope and life cycle, the dependency list and the lint warnings: what a
CI pipeline that does not run Emacs needs.  In batch mode exits with
0 on success and 2 on error."
  (interactive)
  (condition-case err
      (let* ((root (blueprint--root))
             (file (expand-file-name blueprint-ci-report-file root))
             (json (json-serialize (blueprint--ci-report-object root))))
        (with-temp-file file (insert json "\n"))
        (message "Blueprint CI report written to %s" file)
        (when noninteractive (kill-emacs 0))
        file)
    (error
     (message "Blueprint CI export-json: FAIL — %s" (error-message-string err))
     (when noninteractive (kill-emacs 2)))))

(provide 'blueprint-ci)
;;; blueprint-ci.el ends here
