;;; blueprint-test-delivery.el --- Tests for blueprint-delivery.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for `blueprint-pre-delivery-check' and the delivery helper functions.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-delivery)

;;; --- blueprint--delivery-check-master-sync ---

(ert-deftest blueprint-test-delivery/master-no-file ()
  "Returns nil when master.org does not exist."
  (blueprint-test--with-project
    (should-not (blueprint--delivery-check-master-sync))))

(ert-deftest blueprint-test-delivery/master-no-marker ()
  "Returns nil when master.org lacks sync markers."
  (blueprint-test--with-project
    (with-temp-file (expand-file-name "master.org" default-directory)
      (insert "#+TITLE: Assessment\n\nSome content.\n"))
    (should-not (blueprint--delivery-check-master-sync))))

(ert-deftest blueprint-test-delivery/master-has-marker ()
  "Returns non-nil when master.org contains the sync start marker."
  (blueprint-test--with-project
    (with-temp-file (expand-file-name "master.org" default-directory)
      (insert "#+TITLE: Assessment\n\n# @@blueprint-sync-start@@\n# @@blueprint-sync-end@@\n"))
    (should (blueprint--delivery-check-master-sync))))

;;; --- blueprint-pre-delivery-check ---

(ert-deftest blueprint-test-delivery/check-creates-buffer ()
  "blueprint-pre-delivery-check creates and switches to the report buffer."
  (blueprint-test--with-project
    (blueprint-pre-delivery-check)
    (should (get-buffer "*Blueprint Pre-Delivery Check*"))))

(ert-deftest blueprint-test-delivery/check-has-score ()
  "Report buffer contains the health score."
  (blueprint-test--with-project
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (should (string-match-p "Health score" (buffer-string))))))

(ert-deftest blueprint-test-delivery/check-clean-project ()
  "A project with no markers and no components reports PRONTO."
  (blueprint-test--with-project
    (with-temp-file (expand-file-name "master.org" default-directory)
      (insert "# @@blueprint-sync-start@@\n# @@blueprint-sync-end@@\n"))
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (should (string-match-p "PRONTO" (buffer-string))))))

(ert-deftest blueprint-test-delivery/check-warns-on-da-validare ()
  "Report shows ATTENZIONE when [DA VALIDARE] markers are present."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc"
     "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n\n[DA VALIDARE]\n* Introduction\n\n* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n")
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (should (string-match-p "ATTENZIONE" (buffer-string))))))

(ert-deftest blueprint-test-delivery/check-warns-on-missing-master ()
  "Report shows ATTENZIONE when master.org lacks sync markers."
  (blueprint-test--with-project
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      ;; master.org doesn't exist → master sync check fails
      (should (string-match-p "ATTENZIONE" (buffer-string))))))

(provide 'blueprint-test-delivery)
;;; blueprint-test-delivery.el ends here
