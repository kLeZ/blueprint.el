;;; blueprint-test-delivery.el --- Tests for blueprint-delivery.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for `blueprint-pre-delivery-check' and the delivery helper functions.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-delivery)
(require 'blueprint-dashboard)

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

(ert-deftest blueprint-test-delivery/findings-do-not-warn ()
  "[FINDING] markers are reported for information, never as a warning.
A project whose only markers are findings is ready for delivery.
master.org includes both documents: only included files count."
  (blueprint-test--with-project
    (with-temp-file (expand-file-name "master.org" default-directory)
      (insert "#+TITLE: Doc\n\n* Parte II\n\nText.\n\n"
              "# @@blueprint-sync-start@@\n"
              "#+INCLUDE: \".blueprint/components/svc/arc42.org\" :minlevel 3\n"
              "#+INCLUDE: \".blueprint/components/svc/functional.org\" :minlevel 3\n"
              "# @@blueprint-sync-end@@\n"))
    (blueprint-test--write-component
     "svc"
     (concat "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n\n"
             (mapconcat (lambda (h) (format "* %s\n\nText of %s.\n\n" h h))
                        blueprint--lint-expected-headings "")
             "[FINDING] the batch runs twice.\n"))
    (blueprint-test--write-document
     "svc" "functional.org" "#+TITLE: f\n\n* Area\n\n[FINDING] no audit.\n")
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (let ((report (buffer-string)))
        (should (string-match-p "\\[FINDING\\].* 2  \\[INFO\\]" report))
        (should-not (string-match-p "ATTENZIONE" report))
        (should (string-match-p "PRONTO PER LA CONSEGNA" report))))))

(ert-deftest blueprint-test-delivery/findings-do-not-add-to-warn-count ()
  "With other warnings, findings are not counted among them."
  (blueprint-test--with-project
    ;; No master.org: one warning.  Findings must not make it two.
    (blueprint-test--write-component
     "svc"
     (concat "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n\n"
             (mapconcat (lambda (h) (format "* %s\n\nText of %s.\n\n" h h))
                        blueprint--lint-expected-headings "")
             "[FINDING] one.\n"))
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (should (string-match-p "Risultato: 1 verifica/he" (buffer-string))))))

(ert-deftest blueprint-test-delivery/counts-included-files-only ()
  "Markers in files master.org does not include are not counted.
Regression (PLAN 9.31): the check counted [DA VALIDARE] in every Org
file under the root, knowledge base and interview notes included."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" "#+TITLE: svc\n\n* Introduction\n\nTesto [DA VALIDARE].\n")
    (blueprint-test--write-file
     "master.org"
     (concat "#+TITLE: Doc\n\n* Parte 0\n\nPremessa [DA VALIDARE].\n"
             "# @@blueprint-sync-start@@\n"
             "#+INCLUDE: \".blueprint/components/svc/arc42.org\" :minlevel 3\n"
             "# @@blueprint-sync-end@@\n"
             "#+INCLUDE: \"nfr/risks.org\" :minlevel 2\n"))
    (blueprint-test--write-file "nfr/risks.org" "* Rischi\n\nR-1 [DA REVISIONARE].\n")
    (blueprint-test--write-file "kb/notes.org" "[DA VALIDARE] [DA VALIDARE]\n")
    (blueprint-test--write-file "DOMANDE.org" "[DA REVISIONARE] [DA VALIDARE]\n")
    (should (= 2 (blueprint--delivery-count-marker "[DA VALIDARE]")))
    (should (= 1 (blueprint--delivery-count-marker "[DA REVISIONARE]")))
    ;; Same numbers as the DA VAL column of the dashboard rows.
    (should (= 2 (apply #'+ (mapcar (lambda (e) (string-to-number (aref (cadr e) 8)))
                                    (let ((blueprint-dashboard-focus nil)
                                          (blueprint-dashboard-out-of-scope-only nil))
                                      (blueprint--dashboard-entries))))))
    (blueprint-pre-delivery-check)
    (with-current-buffer "*Blueprint Pre-Delivery Check*"
      (should (string-match-p "\\[DA VALIDARE\\] residui +2 " (buffer-string))))))

(provide 'blueprint-test-delivery)
;;; blueprint-test-delivery.el ends here
