;;; blueprint-test-c4.el --- Tests for blueprint-c4.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for Org keyword extraction and C4 PlantUML generation.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-c4)

;;; --- blueprint--org-keyword ---

(ert-deftest blueprint-test-org-keyword/present ()
  "Extracts the value of an Org keyword when present."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: MyComp\n#+BLUEPRINT_DEPENDS: auth db\n\n* Intro\n"))
          (should (equal "auth db"
                         (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
          (should (equal "MyComp"
                         (blueprint--org-keyword file "TITLE"))))
      (delete-file file))))

(ert-deftest blueprint-test-org-keyword/absent ()
  "Returns nil when the keyword is not present."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Intro\n\nNo keywords here.\n"))
          (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))
      (delete-file file))))

(ert-deftest blueprint-test-org-keyword/nil-file ()
  "Returns nil for a nil file without error."
  (should (null (blueprint--org-keyword nil "TITLE"))))

(ert-deftest blueprint-test-org-keyword/missing-file ()
  "Returns nil for a non-existent file without error."
  (should (null (blueprint--org-keyword "/tmp/does-not-exist.org" "TITLE"))))

(ert-deftest blueprint-test-org-keyword/empty-value ()
  "Returns nil when keyword has no value (trailing whitespace only)."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "#+BLUEPRINT_DEPENDS:   \n"))
          (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))
      (delete-file file))))

(ert-deftest blueprint-test-org-keyword/empty-does-not-read-next-line ()
  "An empty keyword is nil, not the text of the following line.
Regression: \"\\s-*\" in the old regex crossed the newline, so an empty
#+BLUEPRINT_DEPENDS: returned \"#+BLUEPRINT_OWNER:\"."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+BLUEPRINT_DEPENDS:\n#+BLUEPRINT_OWNER:\n#+BLUEPRINT_TECH: Java\n"))
          (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
          (should (null (blueprint--org-keyword file "BLUEPRINT_OWNER")))
          (should (equal "Java" (blueprint--org-keyword file "BLUEPRINT_TECH"))))
      (delete-file file))))

(ert-deftest blueprint-test-org-keyword/ignores-src-block-examples ()
  "A keyword line shown inside a src block is not a keyword."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+BLUEPRINT_DEPENDS:\n\n* Guida :noexport:\n"
                    "#+BEGIN_SRC org\n#+BLUEPRINT_DEPENDS: order-service\n#+END_SRC\n"))
          (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))
      (delete-file file))))

(ert-deftest blueprint-test-org-keyword/fresh-component-has-no-deps ()
  "A component created from the system template declares no dependency.
Regression: the example in the template's :noexport: guide was read as
the component's own dependencies by lint, CI, dashboard and risks."
  (blueprint-test--with-project
    (blueprint-add-component "svc")
    (let ((file (blueprint--component-file "svc")))
      (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
      (should (null (blueprint--org-keyword file "BLUEPRINT_OWNER")))
      (should (equal "in-scope" (blueprint--org-keyword file "BLUEPRINT_STATUS"))))))

(ert-deftest blueprint-test-org-keyword/cache-follows-file-changes ()
  "A cached keyword value is re-read after the file changes."
  (let ((file (make-temp-file "bp-kw-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "#+BLUEPRINT_DEPENDS: a\n"))
          (should (equal "a" (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
          (with-temp-file file (insert "#+BLUEPRINT_DEPENDS: b c\n"))
          ;; Same second on coarse-mtime filesystems: size differs too.
          (should (equal "b c" (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))
      (delete-file file))))

;;; --- blueprint-generate-c4 ---

(ert-deftest blueprint-test-c4/no-components ()
  "C4 generation with no components produces a valid empty diagram."
  (blueprint-test--with-project
    (blueprint-generate-c4)
    (let ((outfile (expand-file-name "c4.puml" default-directory)))
      (should (file-exists-p outfile))
      (let ((content (blueprint-test--read-file outfile)))
        (should (string-match-p "@startuml" content))
        (should (string-match-p "@enduml" content))))))

(ert-deftest blueprint-test-c4/single-component ()
  "C4 generation with one component includes a Container entry."
  (blueprint-test--with-project
    (blueprint-test--write-component "api")
    (blueprint-generate-c4)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "c4.puml" default-directory))))
      (should (string-match-p "Container(api" content)))))

(ert-deftest blueprint-test-c4/dependency-relation ()
  "C4 generation includes Rel entries for BLUEPRINT_DEPENDS."
  (blueprint-test--with-project
    (blueprint-test--write-component "frontend")
    (blueprint-test--write-component
     "backend"
     "#+TITLE: backend\n#+BLUEPRINT_DEPENDS: frontend\n\n* Introduction\n\nText.\n")
    (blueprint-generate-c4)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "c4.puml" default-directory))))
      (should (string-match-p "Rel(backend, frontend" content)))))

(ert-deftest blueprint-test-c4/multiple-deps ()
  "Multiple BLUEPRINT_DEPENDS produce multiple Rel entries."
  (blueprint-test--with-project
    (blueprint-test--write-component "a")
    (blueprint-test--write-component "b")
    (blueprint-test--write-component
     "c"
     "#+TITLE: c\n#+BLUEPRINT_DEPENDS: a b\n\n* Introduction\n\nText.\n")
    (blueprint-generate-c4)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "c4.puml" default-directory))))
      (should (string-match-p "Rel(c, a" content))
      (should (string-match-p "Rel(c, b" content)))))

(ert-deftest blueprint-test-c4/overwrites-existing ()
  "Subsequent calls overwrite the existing c4.puml."
  (blueprint-test--with-project
    (blueprint-generate-c4)
    (blueprint-test--write-component "newcomp")
    (blueprint-generate-c4)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "c4.puml" default-directory))))
      (should (string-match-p "newcomp" content)))))

;;; --- blueprint-generate-enterprise-c4 ---

(defun blueprint-test--write-enterprise-context ()
  "Write a minimal enterprise/context.org with the sync markers in place.
Mirrors the shape shipped in templates/enterprise-context.org, but
trimmed to the parts these tests care about."
  (let ((file (expand-file-name "enterprise/context.org" default-directory)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert
       "#+TITLE: Enterprise context\n\n"
       "#+begin_src plantuml :file enterprise-context.svg\n"
       "!include <C4/C4_Context>\n"
       blueprint-enterprise-c4-start-marker "\n"
       blueprint-enterprise-c4-end-marker "\n"
       "System_Ext(ext_1, \"External\", \"\")\n"
       "Rel(ext_1, sys_a, \"calls\")\n"
       "@enduml\n"
       "#+end_src\n"))
    file))

(ert-deftest blueprint-test-enterprise-c4/errors-without-file ()
  "Signals a user-error when enterprise/context.org does not exist."
  (blueprint-test--with-project
    (should-error (blueprint-generate-enterprise-c4) :type 'user-error)))

(ert-deftest blueprint-test-enterprise-c4/errors-without-markers ()
  "Signals a user-error when the file exists but has no sync markers."
  (blueprint-test--with-project
    (let ((file (expand-file-name "enterprise/context.org" default-directory)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert "#+TITLE: Enterprise context\n\nNo markers here.\n")))
    (should-error (blueprint-generate-enterprise-c4) :type 'user-error)))

(ert-deftest blueprint-test-enterprise-c4/adds-system-per-component ()
  "Every component becomes a System(...) entry between the markers."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-enterprise-context)))
      (blueprint-test--write-component "svc")
      (blueprint-generate-enterprise-c4)
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "System(svc, \"svc\", \"\")" content))))))

(ert-deftest blueprint-test-enterprise-c4/adds-rel-for-dependency ()
  "BLUEPRINT_DEPENDS becomes a Rel(...) entry between the markers."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-enterprise-context)))
      (blueprint-test--write-component "frontend")
      (blueprint-test--write-component
       "backend"
       "#+TITLE: backend\n#+BLUEPRINT_DEPENDS: frontend\n\n* Introduction\n\nText.\n")
      (blueprint-generate-enterprise-c4)
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "Rel(backend, frontend" content))))))

(ert-deftest blueprint-test-enterprise-c4/preserves-manual-content ()
  "External systems and manual relations outside the markers survive."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-enterprise-context)))
      (blueprint-test--write-component "sys_a")
      (blueprint-generate-enterprise-c4)
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "System_Ext(ext_1" content))
        (should (string-match-p "Rel(ext_1, sys_a, \"calls\")" content))))))

(ert-deftest blueprint-test-enterprise-c4/second-call-updates ()
  "A second call reflects a newly added component and drops removed ones."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-enterprise-context)))
      (blueprint-test--write-component "old")
      (blueprint-generate-enterprise-c4)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (blueprint-delete-component "old"))
      (blueprint-test--write-component "new")
      (blueprint-generate-enterprise-c4)
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "System(new, \"new\", \"\")" content))
        (should-not (string-match-p "System(old, \"old\", \"\")" content))))))

;;; --- blueprint--component-scope-status ---

(ert-deftest blueprint-test-scope-status/reads-out-of-scope ()
  (blueprint-test--with-project
    (blueprint-test--write-component
     "legacy"
     "#+TITLE: legacy\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\n")
    (should (equal "out-of-scope" (blueprint--component-scope-status "legacy")))))

(ert-deftest blueprint-test-scope-status/reads-tbd ()
  (blueprint-test--with-project
    (blueprint-test--write-component
     "undecided"
     "#+TITLE: undecided\n#+BLUEPRINT_STATUS: tbd\n\n* Introduction\n\n")
    (should (equal "tbd" (blueprint--component-scope-status "undecided")))))

(ert-deftest blueprint-test-scope-status/defaults-in-scope-when-absent ()
  "A component predating this feature (no #+BLUEPRINT_STATUS:) defaults
to in-scope."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (should (equal "in-scope" (blueprint--component-scope-status "svc")))))

(ert-deftest blueprint-test-scope-status/defaults-in-scope-when-unrecognized ()
  "An unrecognized #+BLUEPRINT_STATUS: value falls back to in-scope."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "typo"
     "#+TITLE: typo\n#+BLUEPRINT_STATUS: outof-scope\n\n* Introduction\n\n")
    (should (equal "in-scope" (blueprint--component-scope-status "typo")))))

;;; --- blueprint--component-lifecycle-status ---

(ert-deftest blueprint-test-lifecycle/reads-explicit-value ()
  (blueprint-test--with-project
    (blueprint-test--write-component
     "old"
     "#+TITLE: old\n#+BLUEPRINT_LIFECYCLE: deprecated\n\n* Introduction\n\n")
    (should (equal "deprecated" (blueprint--component-lifecycle-status "old")))))

(ert-deftest blueprint-test-lifecycle/defaults-active-when-absent ()
  "A component predating this feature (no #+BLUEPRINT_LIFECYCLE:)
defaults to active, so existing projects keep working."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (should (equal "active" (blueprint--component-lifecycle-status "svc")))))

(ert-deftest blueprint-test-lifecycle/defaults-active-when-unrecognized ()
  "An unrecognized #+BLUEPRINT_LIFECYCLE: value falls back to active."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "typo"
     "#+TITLE: typo\n#+BLUEPRINT_LIFECYCLE: running\n\n* Introduction\n\n")
    (should (equal "active" (blueprint--component-lifecycle-status "typo")))))

(ert-deftest blueprint-test-lifecycle/independent-from-scope-status ()
  "The two keyword axes do not interfere: a deprecated component can be
in-scope, and changing one does not touch the other."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "legacy"
     (concat "#+TITLE: legacy\n#+BLUEPRINT_STATUS: in-scope\n"
             "#+BLUEPRINT_LIFECYCLE: deprecated\n\n* Introduction\n\n"))
    (should (equal "deprecated" (blueprint--component-lifecycle-status "legacy")))
    (should (equal "in-scope" (blueprint--component-scope-status "legacy")))))

(provide 'blueprint-test-c4)
;;; blueprint-test-c4.el ends here
