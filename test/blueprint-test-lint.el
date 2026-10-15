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
(require 'blueprint-ci)

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

(ert-deftest blueprint-test-lint/empty-content-ignores-noexport ()
  "Text only inside :noexport: or COMMENT subtrees does not count as content."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "guided"
                 (concat "#+TITLE: guided\n\n"
                         "* Guida alla compilazione :noexport:\n"
                         "Esempio fittizio: PiattaformaPagamenti.\n"
                         "| Aspetto | Approccio |\n|---+---|\n| Logging | JSON |\n\n"
                         "* COMMENT Appunti\nNota interna.\n\n"
                         "* Introduction\n\n* Context and Scope\n"))))
      (should (cl-some (lambda (w) (string-match-p "no content" w))
                       (blueprint--lint-component "guided" file))))))

(ert-deftest blueprint-test-lint/content-outside-noexport-counts ()
  "Real text next to a :noexport: guide is content."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "filled"
                 (concat "#+TITLE: filled\n\n"
                         "* Guida :noexport:\nEsempio.\n\n"
                         "* Introduction\nIl servizio gestisce gli ordini.\n"))))
      (should-not (cl-some (lambda (w) (string-match-p "no content" w))
                           (blueprint--lint-component "filled" file))))))

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

(ert-deftest blueprint-test-lint/fresh-template-component-no-dangling-dep ()
  "A component fresh from the system template reports no unknown dependency.
Regression: the #+BLUEPRINT_DEPENDS: example in the template's
:noexport: guide was read as a real dependency on order-service and
notification-service, so `blueprint-ci-validate' failed on every new
project."
  (blueprint-test--with-project
    (blueprint-add-component "svc")
    (should-not (cl-some (lambda (w) (string-match-p "unknown component" w))
                         (blueprint--lint-component
                          "svc" (blueprint--component-file "svc"))))))

;;; --- Lint of every file of the document (PLAN 9.31) ---

(defun blueprint-test--full-arc42 (name)
  "Return an arc42.org body for NAME with every expected heading and text."
  (concat "#+TITLE: " name "\n#+BLUEPRINT_DEPENDS:\n\n"
          (mapconcat (lambda (h) (format "* %s\n\nText of %s.\n\n" h h))
                     blueprint--lint-expected-headings "")))

(ert-deftest blueprint-test-lint/project-checks-included-files ()
  "Marker threshold and empty content run on every included file.
Arc42 headings are checked on arc42.org only, not on the other files."
  (blueprint-test--with-project
    (let ((blueprint-lint-marker-threshold 2))
      (blueprint-test--write-component "svc" (blueprint-test--full-arc42 "svc"))
      (blueprint-test--write-document
       "svc" "functional.org" "#+TITLE: f\n\n* A\n\nTBD TBD TBD\n")
      (blueprint-test--write-master ".blueprint/components/svc/arc42.org"
                                    ".blueprint/components/svc/functional.org"
                                    "nfr/risks.org" "glossary.org")
      (blueprint-test--write-file "nfr/risks.org" "* R\n\nQUESTION QUESTION FIXME\n")
      (blueprint-test--write-file "glossary.org" "#+TITLE: G\n\n* Glossario\n")
      (let ((warnings (blueprint--lint-project)))
        (should (member "svc/functional.org: 3 unresolved markers (0 QUESTION, 3 TBD, 0 FIXME)"
                        warnings))
        (should (member "nfr/risks.org: 3 unresolved markers (2 QUESTION, 0 TBD, 1 FIXME)"
                        warnings))
        (should (member "glossary.org: file has no content (only headings, keywords and anchors)"
                        warnings))
        (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                             warnings))))))

(ert-deftest blueprint-test-lint/project-skips-files-not-included ()
  "Files outside the document are not linted for content."
  (blueprint-test--with-project
    (let ((blueprint-lint-marker-threshold 0))
      (blueprint-test--write-component "svc" (blueprint-test--full-arc42 "svc"))
      (blueprint-test--write-document "svc" "functional.org" "#+TITLE: f\n\nTBD\n")
      (blueprint-test--write-master "glossary.org")
      (blueprint-test--write-file "glossary.org" "* G\n\nTermine.\n")
      (blueprint-test--write-file "notes.org" "QUESTION\n")
      ;; svc is not in master.org: only its structural checks run.
      (should (null (blueprint--lint-project))))))

(ert-deftest blueprint-test-lint/project-missing-include ()
  "An #+INCLUDE: of a missing file is a lint warning."
  (blueprint-test--with-project
    (blueprint-test--write-master "nfr/ghost.org")
    (should (equal (blueprint--lint-project)
                   '("master.org: included file \"nfr/ghost.org\" not found")))))

(ert-deftest blueprint-test-lint/ci-lint-exit-code-from-included-files ()
  "`blueprint-ci-lint' fails on a warning found in an included part."
  (blueprint-test--with-project
    (let ((blueprint-lint-marker-threshold 0)
          (code nil))
      (blueprint-test--write-master "nfr/risks.org")
      (blueprint-test--write-file "nfr/risks.org" "* R\n\nQUESTION\n")
      (cl-letf (((symbol-function 'kill-emacs) (lambda (c) (setq code c)))
                ((symbol-function 'message) #'ignore))
        (let ((noninteractive t))
          (blueprint-ci-lint)))
      (should (equal code 1)))))

(provide 'blueprint-test-lint)
;;; blueprint-test-lint.el ends here
