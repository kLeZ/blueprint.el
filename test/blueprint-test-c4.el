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

(provide 'blueprint-test-c4)
;;; blueprint-test-c4.el ends here
