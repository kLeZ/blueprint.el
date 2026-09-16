;;; blueprint-test-lint.el --- Tests for blueprint-lint.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the linter: missing files, missing headings, marker
;; thresholds, dangling dependencies, and empty content detection.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-lint)

;;; --- blueprint--lint-component ---

(ert-deftest blueprint-test-lint/nil-file-reported ()
  "A nil file path is reported as an error (not silently ignored)."
  (blueprint-test--with-project
    (let ((warnings (blueprint--lint-component "ghost" nil)))
      (should (listp warnings))
      (should (> (length warnings) 0))
      (should (string-match-p "not found" (car warnings))))))

(ert-deftest blueprint-test-lint/missing-file-reported ()
  "A non-existent file is reported as an error."
  (blueprint-test--with-project
    (let ((warnings (blueprint--lint-component
                     "ghost"
                     "/tmp/this-does-not-exist/arc42.org")))
      (should (listp warnings))
      (should (> (length warnings) 0))
      (should (string-match-p "not found" (car warnings))))))

(ert-deftest blueprint-test-lint/full-template-passes-headings ()
  "A component with all required headings has no heading warnings."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component "full")))
      (let ((warnings (blueprint--lint-component "full" file)))
        ;; Heading warnings are of the form "FILE:ID: missing heading ..."
        (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                             warnings))))))

(ert-deftest blueprint-test-lint/missing-heading-detected ()
  "A missing Arc42 heading is reported."
  (blueprint-test--with-project
    (let* ((dir (expand-file-name ".blueprint/components/partial" default-directory))
           (file (expand-file-name "arc42.org" dir)))
      (make-directory dir t)
      (with-temp-file file
        ;; Only Introduction — many required headings missing
        (insert "#+TITLE: partial\n\n* Introduction\n\nSome content here.\n"))
      (let ((warnings (blueprint--lint-component "partial" file)))
        (should (cl-some (lambda (w) (string-match-p "missing heading" w))
                         warnings))))))

(ert-deftest blueprint-test-lint/marker-threshold ()
  "More than `blueprint-lint-marker-threshold' markers triggers a warning."
  (blueprint-test--with-project
    (let ((blueprint-lint-marker-threshold 2))
      (let* ((dir (expand-file-name ".blueprint/components/noisy" default-directory))
             (file (expand-file-name "arc42.org" dir)))
        (make-directory dir t)
        (with-temp-file file
          (insert "#+TITLE: noisy\n\n"
                  "* Introduction\n\nTBD one\nTBD two\nTBD three\n"))
        (let ((warnings (blueprint--lint-component "noisy" file)))
          (should (cl-some (lambda (w) (string-match-p "unresolved markers" w))
                           warnings)))))))

(ert-deftest blueprint-test-lint/marker-below-threshold-no-warning ()
  "Fewer markers than the threshold produce no marker warning."
  (blueprint-test--with-project
    (let ((blueprint-lint-marker-threshold 10))
      (let* ((dir (expand-file-name ".blueprint/components/quiet" default-directory))
             (file (expand-file-name "arc42.org" dir)))
        (make-directory dir t)
        (with-temp-file file
          (insert (blueprint-test--write-component "quiet")))
        ;; Reuse the helper which writes a clean file
        (let ((file2 (blueprint-test--write-component "quiet2")))
          (let ((warnings (blueprint--lint-component "quiet2" file2)))
            (should-not (cl-some (lambda (w) (string-match-p "unresolved markers" w))
                                 warnings))))))))

(ert-deftest blueprint-test-lint/empty-content-detected ()
  "A file with only headings and keywords but no prose is reported."
  (blueprint-test--with-project
    (let* ((dir (expand-file-name ".blueprint/components/empty" default-directory))
           (file (expand-file-name "arc42.org" dir)))
      (make-directory dir t)
      (with-temp-file file
        (insert "#+TITLE: empty\n#+BLUEPRINT_DEPENDS:\n\n"
                "* Introduction\n\n"
                "* Context and Scope\n\n"
                "* Constraints\n\n"
                "* Solution Strategy\n\n"
                "* Building Blocks\n\n"
                "* Runtime Behavior\n\n"
                "* Deployment\n\n"
                "* Responsibility\n\n"
                "* Risks\n\n"
                "* Open Questions\n\n"
                "* Diagrams\n"))
      (let ((warnings (blueprint--lint-component "empty" file)))
        (should (cl-some (lambda (w) (string-match-p "no content" w))
                         warnings))))))

(ert-deftest blueprint-test-lint/binary-content-no-crash ()
  "Linting a component file with invalid-UTF-8 / binary bytes does not
error.  The binary line itself counts as \"content\" (the empty-content
check does not distinguish valid prose from garbage bytes, only
blank/heading/keyword lines from everything else), so this asserts
graceful handling -- a warning list is still produced, missing
headings are still detected -- not the specific \"no content\" case."
  (blueprint-test--with-project
    (let* ((dir (expand-file-name ".blueprint/components/corrupt" default-directory))
           (file (expand-file-name "arc42.org" dir)))
      (make-directory dir t)
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (insert "#+TITLE: corrupt\n")
        (insert (unibyte-string 0 255 254 1 2 3))
        (insert "\n")
        (write-region (point-min) (point-max) file))
      (let ((warnings (blueprint--lint-component "corrupt" file)))
        (should (listp warnings))
        (should (cl-some (lambda (w) (string-match-p "missing heading" w))
                         warnings))))))

(ert-deftest blueprint-test-lint/dangling-dep-detected ()
  "A BLUEPRINT_DEPENDS referencing a non-existent component is reported."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "loner"
                 "#+TITLE: loner\n#+BLUEPRINT_DEPENDS: ghost-comp\n\n* Introduction\n\nText.\n")))
      (let ((warnings (blueprint--lint-component "loner" file)))
        (should (cl-some (lambda (w) (string-match-p "unknown component" w))
                         warnings))))))

(ert-deftest blueprint-test-lint/valid-dep-no-warning ()
  "A BLUEPRINT_DEPENDS referencing an existing component produces no warning."
  (blueprint-test--with-project
    (blueprint-test--write-component "service-b")
    (let ((file (blueprint-test--write-component
                 "service-a"
                 "#+TITLE: service-a\n#+BLUEPRINT_DEPENDS: service-b\n\n* Introduction\n\nText here.\n")))
      (let ((warnings (blueprint--lint-component "service-a" file)))
        (should-not (cl-some (lambda (w) (string-match-p "unknown component" w))
                             warnings))))))

;;; --- perimeter status (#+BLUEPRINT_STATUS:) ---

(ert-deftest blueprint-test-lint/in-scope-depending-on-out-of-scope-warns ()
  "An in-scope component depending on an out-of-scope one is flagged."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "legacy-billing"
     "#+TITLE: legacy-billing\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\nText.\n")
    (let ((file (blueprint-test--write-component
                 "order-service"
                 (concat "#+TITLE: order-service\n"
                         "#+BLUEPRINT_DEPENDS: legacy-billing\n"
                         "#+BLUEPRINT_STATUS: in-scope\n\n"
                         "* Introduction\n\nText.\n"))))
      (let ((warnings (blueprint--lint-component "order-service" file)))
        (should (cl-some (lambda (w) (string-match-p "out-of-scope" w))
                         warnings))))))

(ert-deftest blueprint-test-lint/out-of-scope-depending-on-out-of-scope-no-warning ()
  "An out-of-scope component depending on another out-of-scope one is fine."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "legacy-billing"
     "#+TITLE: legacy-billing\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\nText.\n")
    (let ((file (blueprint-test--write-component
                 "legacy-reports"
                 (concat "#+TITLE: legacy-reports\n"
                         "#+BLUEPRINT_DEPENDS: legacy-billing\n"
                         "#+BLUEPRINT_STATUS: out-of-scope\n\n"
                         "* Introduction\n\nText.\n"))))
      (let ((warnings (blueprint--lint-component "legacy-reports" file)))
        (should-not (cl-some (lambda (w) (string-match-p "out-of-scope" w))
                             warnings))))))

(ert-deftest blueprint-test-lint/missing-status-defaults-in-scope-no-warning ()
  "A component with no #+BLUEPRINT_STATUS: (pre-existing project) is
treated as in-scope, but depending on an in-scope component raises no
out-of-scope warning."
  (blueprint-test--with-project
    (blueprint-test--write-component "service-b")
    (let ((file (blueprint-test--write-component
                 "service-a"
                 "#+TITLE: service-a\n#+BLUEPRINT_DEPENDS: service-b\n\n* Introduction\n\nText here.\n")))
      (let ((warnings (blueprint--lint-component "service-a" file)))
        (should-not (cl-some (lambda (w) (string-match-p "out-of-scope" w))
                             warnings))))))

;;; --- blueprint-lint (interactive) ---

(ert-deftest blueprint-test-lint/no-components-clean ()
  "Linting an empty project produces no warnings."
  (blueprint-test--with-project
    ;; Should not error; returns nil or shows "all clear"
    (should (progn (blueprint-lint) t))))

(provide 'blueprint-test-lint)
;;; blueprint-test-lint.el ends here
