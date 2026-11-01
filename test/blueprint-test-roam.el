;;; blueprint-test-roam.el --- Tests for blueprint-roam.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the org-roam integration.  The pure logic (dependency
;; clusters, similarity score, title tokens) is tested for real; the
;; commands that need the org-roam database are skipped when org-roam
;; is not installed (as in CI).

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-roam)
(require 'blueprint-graph)

;;; --- Pure logic ---

(ert-deftest blueprint-test-roam/tokens-lowercase-and-split ()
  "Titles split into lowercase alphanumeric tokens."
  (should (equal (blueprint--roam-tokens "Order Service API")
                 '("order" "service" "api")))
  (should (null (blueprint--roam-tokens nil))))

(ert-deftest blueprint-test-roam/similarity-weights ()
  "Shared tags and links weigh 2, shared title tokens 1."
  (should (= 5 (blueprint--roam-similarity
                '("payments") '("db") "Order Service"
                '("payments") '("db") "Order Management")))
  (should (= 1 (blueprint--roam-similarity
                nil nil "Order Service" nil nil "Order Management")))
  (should (zerop (blueprint--roam-similarity
                  nil nil "Cassa" nil nil "Warehouse"))))

(ert-deftest blueprint-test-graph/dependency-clusters ()
  "Components joined by a dependency chain share a cluster; isolated
components are clusters of their own; unknown deps are ignored."
  (let* ((deps '(("api" . ("payments" "ghost"))
                 ("payments" . ("db"))
                 ("db" . ())
                 ("frontend" . ("api"))
                 ("warehouse" . ())))
         (clusters (blueprint--dependency-clusters deps)))
    (should (= 2 (length clusters)))
    ;; Largest cluster first, ids alphabetical inside.
    (should (equal (car clusters) '("api" "db" "frontend" "payments")))
    (should (equal (cadr clusters) '("warehouse")))))

(ert-deftest blueprint-test-graph/dependency-clusters-empty ()
  "No dependencies: every component is its own cluster."
  (should (null (blueprint--dependency-clusters nil)))
  (should (equal (blueprint--dependency-clusters '(("a" . nil) ("b" . nil)))
                 '(("a") ("b")))))

;;; --- Commands (need org-roam) ---

(ert-deftest blueprint-test-roam/similar-requires-org-roam ()
  "Without org-roam the command says so instead of erroring obscurely."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (if (blueprint--roam-available-p)
        (ert-skip "org-roam installed: the graceful-error path is not exercised")
      (should-error (blueprint-roam-similar "svc") :type 'user-error))))

(ert-deftest blueprint-test-roam/clusters-work-without-org-roam ()
  "The clusters command works with the dependencies alone when
org-roam is missing, and lists every component."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "api" (concat "#+TITLE: api\n#+BLUEPRINT_DEPENDS: payments\n\n"
                   "* Introduction\n"))
    (blueprint-test--write-component
     "payments" (concat "#+TITLE: payments\n#+BLUEPRINT_DEPENDS: db\n\n"
                        "* Introduction\n"))
    (blueprint-test--write-component "warehouse" "#+TITLE: warehouse\n")
    (if (blueprint--roam-available-p)
        (ert-skip "org-roam installed: dependencies-only path not exercised")
      (let ((clusters (blueprint-roam-clusters)))
        (should (= 2 (length clusters)))
        (should (equal (car clusters) '("api" "db" "payments")))))))

(provide 'blueprint-test-roam)
;;; blueprint-test-roam.el ends here
