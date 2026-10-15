;;; blueprint-test-risks.el --- Tests for blueprint-risks.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for deterministic risk pattern matching and structural checks.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-risks)

(defun blueprint-test--risk-descriptions (findings)
  "Return a list of :risk strings from FINDINGS."
  (mapcar (lambda (r) (plist-get r :risk)) findings))

;;; --- blueprint--detect-risks (pattern matching) ---

(ert-deftest blueprint-test-risks/spof-detected ()
  "Single-point-of-failure pattern is detected."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Risks\n\nThis component is a single point of failure.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              (should (member "Single point of failure detected"
                              (blueprint-test--risk-descriptions findings))))))
      (delete-file file))))

(ert-deftest blueprint-test-risks/no-monitoring-detected ()
  "Missing monitoring pattern is detected."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Deployment\n\nNo monitoring in place.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              (should (member "Missing monitoring"
                              (blueprint-test--risk-descriptions findings))))))
      (delete-file file))))

(ert-deftest blueprint-test-risks/deprecated-tech-detected ()
  "Deprecated technology pattern is detected."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Building Blocks\n\nUses a deprecated library.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              (should (member "Deprecated or legacy technology"
                              (blueprint-test--risk-descriptions findings))))))
      (delete-file file))))

(ert-deftest blueprint-test-risks/hardcoded-detected ()
  "Hardcoded values pattern is detected."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Constraints\n\nThe URL is hardcoded in the config.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              (should (member "Hardcoded values or magic numbers"
                              (blueprint-test--risk-descriptions findings))))))
      (delete-file file))))

(ert-deftest blueprint-test-risks/clean-component-no-risks ()
  "A clean component file returns no findings."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Introduction\n\nWell-designed component with full coverage.\n"
                    "* Responsibility\n\nOwned by the backend team.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              ;; Only structural checks might fire (isolated component),
              ;; but no pattern-based risks should appear.
              (should-not (member "Single point of failure detected"
                                  (blueprint-test--risk-descriptions findings)))
              (should-not (member "Missing monitoring"
                                  (blueprint-test--risk-descriptions findings))))))
      (delete-file file))))

;;; --- Structural checks ---

(ert-deftest blueprint-test-risks/immature-docs-detected ()
  "Excessive markers trigger the immature documentation risk."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "messy"
                 (concat "#+TITLE: messy\n\n"
                         "* Section\n\n"
                         ;; 10 markers: exceeds threshold of 8
                         "TBD one\nTBD two\nTBD three\nTBD four\nTBD five\n"
                         "QUESTION a\nQUESTION b\nQUESTION c\nQUESTION d\n"
                         "FIXME here\n"))))
      (blueprint--invalidate-cache)
      (let ((findings (blueprint--detect-risks file)))
        (should (member "Immature documentation (many unresolved markers)"
                        (blueprint-test--risk-descriptions findings)))))))

(ert-deftest blueprint-test-risks/isolated-component-detected ()
  "A component with no dependencies in or out is marked as isolated."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "island"
                 "#+TITLE: island\n#+BLUEPRINT_DEPENDS:\n\n* Introduction\n\nText.\n")))
      (blueprint--invalidate-cache)
      (let ((findings (blueprint--detect-risks file)))
        (should (member "Isolated component (no dependencies in or out)"
                        (blueprint-test--risk-descriptions findings)))))))

(ert-deftest blueprint-test-risks/not-isolated-if-depended-upon ()
  "A component depended upon by others is not flagged as isolated."
  (blueprint-test--with-project
    (let ((dep-file (blueprint-test--write-component
                     "shared"
                     "#+TITLE: shared\n#+BLUEPRINT_DEPENDS:\n\n* Introduction\n\nText.\n")))
      (blueprint-test--write-component
       "consumer"
       "#+TITLE: consumer\n#+BLUEPRINT_DEPENDS: shared\n\n* Introduction\n\nText.\n")
      (blueprint--invalidate-cache)
      (let ((findings (blueprint--detect-risks dep-file)))
        (should-not (member "Isolated component (no dependencies in or out)"
                            (blueprint-test--risk-descriptions findings)))))))

;;; --- Severity levels ---

(ert-deftest blueprint-test-risks/severity-present ()
  "Each finding includes a non-nil :severity."
  (let ((file (make-temp-file "bp-risks-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* S\n\nSingle point of failure and deprecated tech.\n"))
          (blueprint-test--with-project
            (let ((findings (blueprint--detect-risks file)))
              (dolist (f findings)
                (should (plist-get f :severity))))))
      (delete-file file))))

;;; --- Every file of the document (PLAN 9.31) ---

(ert-deftest blueprint-test-risks/patterns-in-included-documents ()
  "Patterns are searched in every document of the component in master.org.
A pattern in a :noexport: subtree does not count."
  (blueprint-test--with-project
    (let ((arc (blueprint-test--write-component
                "svc" "#+TITLE: svc\n\n* Introduction\n\nClean text.\n\n* Guide :noexport:\nNo backup here.\n")))
      (blueprint-test--write-document
       "svc" "infrastructure.org" "#+TITLE: i\n\n* Servers\n\nThe database is a single point of failure.\n")
      (blueprint-test--write-document
       "svc" "functional.org" "#+TITLE: f\n\n* A\n\nThe URL is hardcoded.\n")
      (blueprint-test--write-master ".blueprint/components/svc/arc42.org"
                                    ".blueprint/components/svc/infrastructure.org")
      (let ((risks (blueprint-test--risk-descriptions (blueprint--detect-risks arc))))
        (should (member "Single point of failure detected" risks))
        ;; functional.org is not in master.org.
        (should-not (member "Hardcoded values or magic numbers" risks))
        (should-not (member "No backup strategy" risks))))))

(ert-deftest blueprint-test-risks/immature-over-all-documents ()
  "The immature-documentation check sums the markers of all documents."
  (blueprint-test--with-project
    (let ((arc (blueprint-test--write-component
                "svc" "#+TITLE: svc\n\n* S\n\nTBD TBD TBD TBD TBD\n")))
      (blueprint-test--write-document
       "svc" "functional.org" "#+TITLE: f\n\n* A\n\nQUESTION QUESTION QUESTION QUESTION\n")
      (should (member "Immature documentation (many unresolved markers)"
                      (blueprint-test--risk-descriptions
                       (blueprint--detect-risks arc)))))))

(ert-deftest blueprint-test-risks/all-covers-parts ()
  "`blueprint-suggest-risks-all' also reports files outside the components."
  (blueprint-test--with-project
    (blueprint-test--write-master "nfr/constraints.org")
    (blueprint-test--write-file
     "nfr/constraints.org" "* Vincoli\n\nDeploy is a manual process.\n")
    (blueprint-suggest-risks-all)
    (with-current-buffer "*Blueprint Risks*"
      (should (string-match-p "── nfr/constraints.org ──" (buffer-string)))
      (should (string-match-p "Manual processes present" (buffer-string))))))

(provide 'blueprint-test-risks)
;;; blueprint-test-risks.el ends here
