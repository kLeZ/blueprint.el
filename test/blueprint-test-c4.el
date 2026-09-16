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
          ;; The regex requires a non-space char: \(.*\\S-\)
          (should (null (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))
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

(provide 'blueprint-test-c4)
;;; blueprint-test-c4.el ends here
