;;; blueprint-test-ci.el --- Tests for blueprint-ci.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the CI/headless entry points, with a focus on the JSON
;; report of `blueprint-ci-export-json' (the lint and validate paths
;; are exercised through `blueprint-test-lint.el').

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-ci)

(defun blueprint-test-ci--full-arc42 (title intro &optional extra-keywords)
  "Return an arc42.org body with all the lint-expected headings.
TITLE is the component title, INTRO goes under Introduction and
EXTRA-KEYWORDS sits right after the title line."
  (concat "#+TITLE: " title "\n"
          (or extra-keywords "")
          "\n* Introduction\n\n"
          (or intro "")
          "\n\n* Context and Scope\n\n"
          "* Constraints\n\n"
          "* Solution Strategy\n\n"
          "* Building Blocks\n\n"
          "* Runtime Behavior\n\n"
          "* Deployment\n\n"
          "* Responsibility\n\n"
          "* Risks\n\n"
          "* Open Questions\n\n"
          "* Diagrams\n"))

(defun blueprint-test-ci--write-master ()
  "Write a master.org with the three empty sync-marker sections.
Hand-written instead of `blueprint-sync''s template one, so the
fixture's marker counts are fully predictable (the master template
documents the marking conventions in exported text)."
  (blueprint-test--write-file
   "master.org"
   (concat "#+TITLE: Doc\n\n* Parte 0\n\nIntroduzione.\n\n"
           "# @@blueprint-sync-start@@\n"
           "# @@blueprint-sync-end@@\n\n"
           "# @@blueprint-sync-functional-start@@\n"
           "# @@blueprint-sync-functional-end@@\n\n"
           "# @@blueprint-sync-infra-start@@\n"
           "# @@blueprint-sync-infra-end@@\n")))

(defun blueprint-test-ci--write-project ()
  "Create a fixture project with two synced components.
ALPHA depends on BETA and carries markers, so its counts, penalty and
score in the report are known; both components have all the headings
the lint expects, so the only warning source is what a test adds.
Returns nothing; call inside `blueprint-test--with-project'."
  (blueprint-test-ci--write-master)
  (blueprint-test--write-component
   "alpha"
   (blueprint-test-ci--full-arc42
    "alpha" "Text with QUESTION one."
    "#+BLUEPRINT_DEPENDS: beta\n#+BLUEPRINT_OWNER: Marco\n#+BLUEPRINT_TECH: Java\n"))
  (blueprint-test--write-component
   "beta"
   (blueprint-test-ci--full-arc42 "beta" "Clean text with a FIXME here."))
  (require 'blueprint-sync)
  (blueprint-sync))

(ert-deftest blueprint-test-ci/marker-name-keys ()
  "Marker regexps become readable, stable JSON keys."
  (should (string= "question" (blueprint--ci-report--marker-name "\\<QUESTION\\>")))
  (should (string= "to-validate" (blueprint--ci-report--marker-name blueprint--to-validate-regexp)))
  (should (string= "to-review" (blueprint--ci-report--marker-name blueprint--to-review-regexp))))

(ert-deftest blueprint-test-ci/report-object-health ()
  "The report health block mirrors `blueprint-health-score'."
  (blueprint-test--with-project
    (blueprint-test-ci--write-project)
    (let* ((report (blueprint--ci-report-object))
           (health (gethash "health" report))
           (markers (gethash "markers" health)))
      (should (integerp (gethash "score" health)))
      (should (= (gethash "score" health) (blueprint-health-score)))
      (should (= (gethash "penalty" health) 7)) ; QUESTION 3 + FIXME 4
      (should (= (gethash "question" markers) 1))
      (should (= (gethash "fixme" markers) 1))
      (should (= (gethash "to-validate" markers) 0)))))

(ert-deftest blueprint-test-ci/report-object-components ()
  "Components carry id, scope, owner, tech, depends and markers."
  (blueprint-test--with-project
    (blueprint-test-ci--write-project)
    (let* ((report (blueprint--ci-report-object))
           (components (gethash "components" report))
           (alpha (seq-find (lambda (c) (equal (gethash "id" c) "alpha"))
                            components))
           (beta (seq-find (lambda (c) (equal (gethash "id" c) "beta"))
                           components)))
      (should (= (length components) 2))
      (should (string= (gethash "scope" alpha) "in-scope"))
      (should (string= (gethash "lifecycle" alpha) "active"))
      (should (string= (gethash "owner" alpha) "Marco"))
      (should (string= (gethash "tech" alpha) "Java"))
      (should (equal (gethash "depends" alpha) ["beta"]))
      (should (eq (gethash "included" alpha) t))
      (should (= (gethash "penalty" beta) 4)) ; one FIXME
      (should (= (gethash "question" (gethash "markers" alpha)) 1)))))

(ert-deftest blueprint-test-ci/report-object-dependencies ()
  "Dependencies come out as from/to objects."
  (blueprint-test--with-project
    (blueprint-test-ci--write-project)
    (let ((deps (gethash "dependencies" (blueprint--ci-report-object))))
      (should (seq-find (lambda (d)
                          (and (equal (gethash "from" d) "alpha")
                               (equal (gethash "to" d) "beta")))
                        deps)))))

(ert-deftest blueprint-test-ci/report-object-lint-warnings ()
  "A dangling dependency surfaces in the lint-warnings of the report."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "alpha"
     (blueprint-test-ci--full-arc42
      "alpha" "Some real content so the empty-content check stays quiet."
      "#+BLUEPRINT_DEPENDS: ghost\n"))
    (let ((warnings (gethash "lint-warnings" (blueprint--ci-report-object))))
      (should (= (length warnings) 1))
      (should (string-match-p "ghost" (aref warnings 0))))))

(ert-deftest blueprint-test-ci/export-json-writes-valid-json ()
  "blueprint-ci-export-json writes a file that parses back as JSON."
  (blueprint-test--with-project
    (blueprint-test-ci--write-project)
    (let ((noninteractive nil))
      (should (stringp (blueprint-ci-export-json))))
    (let ((file (expand-file-name "blueprint-report.json" default-directory)))
      (should (file-exists-p file))
      (let* ((json-object-type 'alist)
             (json-key-type 'string)
             (json-array-type 'list)
             (data (json-read-from-string (blueprint-test--read-file file))))
        (should (assoc "health" data))
        (should (assoc "components" data))
        (should (assoc "dependencies" data))
        (should (assoc "lint-warnings" data))
        (should (= (length (cdr (assoc "components" data))) 2))
        (should (string= (cdr (assoc "project" data))
                         (file-name-nondirectory
                          (directory-file-name (blueprint--root)))))))))

(ert-deftest blueprint-test-ci/report-json-null-and-false ()
  "Absent owner/tech are JSON null and a component outside master.org
has \"included\": false: `json-serialize' would write nil as {}."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "alpha"
     (blueprint-test-ci--full-arc42
      "alpha" "Some real content so the empty-content check stays quiet."
      ""))
    (blueprint-test--write-file "master.org" "#+TITLE: M\n\nNothing included.\n")
    (let* ((json (json-serialize (blueprint--ci-report-object)))
           (data (json-parse-string json :null-object 'null
                                    :false-object 'false))
           (alpha (aref (gethash "components" data) 0)))
      (should (eq (gethash "owner" alpha) 'null))
      (should (eq (gethash "tech" alpha) 'null))
      (should (eq (gethash "included" alpha) 'false)))))

(provide 'blueprint-test-ci)
;;; blueprint-test-ci.el ends here
