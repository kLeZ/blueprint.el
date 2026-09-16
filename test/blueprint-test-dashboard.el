;;; blueprint-test-dashboard.el --- Tests for blueprint-dashboard.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for dashboard entry building, status classification, and
;; focus-mode filtering.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-dashboard)

(ert-deftest blueprint-test-dashboard/status-ok-with-no-markers ()
  (should (equal (blueprint--component-status 0 0 0) "OK")))

(ert-deftest blueprint-test-dashboard/status-in-progress-with-few-markers ()
  (should (equal (blueprint--component-status 1 1 0) "IN-PROGRESS")))

(ert-deftest blueprint-test-dashboard/status-needs-work-with-many-questions ()
  (should (equal (blueprint--component-status 3 0 0) "NEEDS-WORK")))

(ert-deftest blueprint-test-dashboard/status-fixme-takes-priority ()
  "A single FIXME outranks question/TBD counts, however low."
  (should (equal (blueprint--component-status 0 0 1) "FIXME")))

(ert-deftest blueprint-test-dashboard/entries-include-all-components ()
  "blueprint--dashboard-entries lists every component when focus is off."
  (blueprint-test--with-project
    (let ((blueprint-dashboard-focus nil))
      (blueprint-test--write-component "alpha")
      (blueprint-test--write-component "beta")
      (let ((ids (mapcar #'car (blueprint--dashboard-entries))))
        (should (member "alpha" ids))
        (should (member "beta" ids))))))

(ert-deftest blueprint-test-dashboard/entries-sorted-by-name ()
  "blueprint--dashboard-entries is sorted alphabetically by component id."
  (blueprint-test--with-project
    (let ((blueprint-dashboard-focus nil))
      (blueprint-test--write-component "zeta")
      (blueprint-test--write-component "alpha")
      (should (equal (mapcar #'car (blueprint--dashboard-entries))
                     '("alpha" "zeta"))))))

(ert-deftest blueprint-test-dashboard/focus-mode-filters-clean-components ()
  "With focus mode on, only components with open markers are listed."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean")
    (blueprint-test--write-component
     "noisy"
     (concat "#+TITLE: noisy\n#+BLUEPRINT_DEPENDS:\n\n"
             "* Open Questions\n\n- QUESTION something unresolved\n"))
    (let* ((blueprint-dashboard-focus t)
           (ids (mapcar #'car (blueprint--dashboard-entries))))
      (should (member "noisy" ids))
      (should-not (member "clean" ids)))))

(ert-deftest blueprint-test-dashboard/entries-carry-owner-and-tech-columns ()
  "Owner/Tech keywords from the component file surface as dashboard columns."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc"
     (concat "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n"
             "#+BLUEPRINT_OWNER: Team Payments\n"
             "#+BLUEPRINT_TECH: Java\n\n* Introduction\n\n"))
    (let* ((blueprint-dashboard-focus nil)
           (entry (assoc "svc" (blueprint--dashboard-entries)))
           (fields (cadr entry)))
      (should (equal (aref fields 1) "Team Payments"))
      (should (equal (aref fields 2) "Java")))))

(ert-deftest blueprint-test-dashboard/line-count-of-missing-file-is-zero ()
  (should (= 0 (blueprint--component-line-count nil)))
  (should (= 0 (blueprint--component-line-count "/nonexistent/path.org"))))

(provide 'blueprint-test-dashboard)
;;; blueprint-test-dashboard.el ends here
