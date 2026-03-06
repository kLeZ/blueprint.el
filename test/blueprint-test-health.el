;;; blueprint-test-health.el --- Tests for blueprint-health.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for component metric counting and health score calculation.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-health)

;;; --- blueprint--component-metrics ---

(ert-deftest blueprint-test-metrics/clean-file ()
  "A file with no markers returns (0 0 0)."
  (let ((file (make-temp-file "bp-metrics-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Introduction\n\nSome text.\n"))
          (should (equal '(0 0 0) (blueprint--component-metrics file))))
      (delete-file file))))

(ert-deftest blueprint-test-metrics/counts-questions ()
  "QUESTION markers are counted."
  (let ((file (make-temp-file "bp-metrics-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Open Questions\n\n- QUESTION first\n- QUESTION second\n"))
          (let ((m (blueprint--component-metrics file)))
            (should (= 2 (nth 0 m)))
            (should (= 0 (nth 1 m)))
            (should (= 0 (nth 2 m)))))
      (delete-file file))))

(ert-deftest blueprint-test-metrics/counts-tbds ()
  "TBD markers are counted."
  (let ((file (make-temp-file "bp-metrics-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Section\n\nTBD: needs work. TBD another.\n"))
          (let ((m (blueprint--component-metrics file)))
            (should (= 0 (nth 0 m)))
            (should (= 2 (nth 1 m)))
            (should (= 0 (nth 2 m)))))
      (delete-file file))))

(ert-deftest blueprint-test-metrics/counts-fixmes ()
  "FIXME markers are counted."
  (let ((file (make-temp-file "bp-metrics-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "FIXME this\nFIXME that\nFIXME again\n"))
          (let ((m (blueprint--component-metrics file)))
            (should (= 0 (nth 0 m)))
            (should (= 0 (nth 1 m)))
            (should (= 3 (nth 2 m)))))
      (delete-file file))))

(ert-deftest blueprint-test-metrics/mixed-markers ()
  "All three marker types are counted independently."
  (let ((file (make-temp-file "bp-metrics-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "QUESTION one\nTBD two\nFIXME three\nQUESTION four\n"))
          (let ((m (blueprint--component-metrics file)))
            (should (= 2 (nth 0 m)))
            (should (= 1 (nth 1 m)))
            (should (= 1 (nth 2 m)))))
      (delete-file file))))

(ert-deftest blueprint-test-metrics/nil-file ()
  "A nil file returns (0 0 0) without error."
  (should (equal '(0 0 0) (blueprint--component-metrics nil))))

(ert-deftest blueprint-test-metrics/missing-file ()
  "A nonexistent file returns (0 0 0) without error."
  (should (equal '(0 0 0)
                 (blueprint--component-metrics "/tmp/this-file-does-not-exist.org"))))

;;; --- blueprint-health-score ---

(ert-deftest blueprint-test-health-score/perfect ()
  "A project with no markers scores 100."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean" "#+TITLE: clean\n\n* Introduction\n\nAll good.\n")
    (blueprint--invalidate-cache)
    (should (= 100 (blueprint-health-score)))))

(ert-deftest blueprint-test-health-score/question-penalty ()
  "Each QUESTION deducts 3 points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Open Questions\n\n- QUESTION one\n- QUESTION two\n")
    (blueprint--invalidate-cache)
    (should (= 94 (blueprint-health-score)))))  ; 100 - 2*3

(ert-deftest blueprint-test-health-score/tbd-penalty ()
  "Each TBD deducts 2 points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Section\n\nTBD here.\n")
    (blueprint--invalidate-cache)
    (should (= 98 (blueprint-health-score)))))  ; 100 - 1*2

(ert-deftest blueprint-test-health-score/fixme-penalty ()
  "Each FIXME deducts 4 points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Section\n\nFIXME urgent.\n")
    (blueprint--invalidate-cache)
    (should (= 96 (blueprint-health-score)))))  ; 100 - 1*4

(ert-deftest blueprint-test-health-score/clamped-at-zero ()
  "Score is never negative."
  (blueprint-test--with-project
    ;; 30 FIXMEs = -120 penalty → clamped to 0
    (blueprint-test--write-component
     "comp"
     (concat "#+TITLE: comp\n\n"
             (mapconcat (lambda (_) "FIXME item\n") (make-list 30 nil) "")))
    (blueprint--invalidate-cache)
    (should (= 0 (blueprint-health-score)))))

(ert-deftest blueprint-test-health-score/multiple-components ()
  "Penalties accumulate across all components."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "a" "#+TITLE: a\n\n* S\n\nQUESTION one\n")   ; -3
    (blueprint-test--write-component
     "b" "#+TITLE: b\n\n* S\n\nFIXME one\n")       ; -4
    (blueprint--invalidate-cache)
    (should (= 93 (blueprint-health-score)))))

(ert-deftest blueprint-test-health-score/empty-project ()
  "An empty project (no components) scores 100."
  (blueprint-test--with-project
    (should (= 100 (blueprint-health-score)))))

;;; --- blueprint--methodology-metrics ---

(ert-deftest blueprint-test-methodology/no-markers ()
  "A file with no methodology markers returns (0 0 0)."
  (let ((file (make-temp-file "bp-method-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Introduction\n\nSome text.\n"))
          (should (equal '(0 0 0) (blueprint--methodology-metrics file))))
      (delete-file file))))

(ert-deftest blueprint-test-methodology/nil-file ()
  "A nil file returns (0 0 0) without error."
  (should (equal '(0 0 0) (blueprint--methodology-metrics nil))))

(ert-deftest blueprint-test-methodology/counts-da-validare ()
  "[DA VALIDARE] occurrences are counted."
  (let ((file (make-temp-file "bp-method-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* A\n[DA VALIDARE]\n* B\n[DA VALIDARE]\n[DA VALIDARE]\n"))
          (should (= 3 (car (blueprint--methodology-metrics file)))))
      (delete-file file))))

(ert-deftest blueprint-test-methodology/counts-findings ()
  "[FINDING] occurrences are counted."
  (let ((file (make-temp-file "bp-method-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Section\n[FINDING] discrepanza A\n[FINDING] discrepanza B\n"))
          (should (= 2 (cadr (blueprint--methodology-metrics file)))))
      (delete-file file))))

(ert-deftest blueprint-test-methodology/counts-da-revisionare ()
  "[DA REVISIONARE] occurrences are counted."
  (let ((file (make-temp-file "bp-method-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Section\n[DA REVISIONARE]\n"))
          (should (= 1 (caddr (blueprint--methodology-metrics file)))))
      (delete-file file))))

(ert-deftest blueprint-test-methodology/mixed-markers ()
  "All three methodology marker types are counted independently."
  (let ((file (make-temp-file "bp-method-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "[DA VALIDARE]\n[FINDING] f1\n[DA REVISIONARE]\n[DA VALIDARE]\n"))
          (pcase-let ((`(,dv ,fi ,dr) (blueprint--methodology-metrics file)))
            (should (= 2 dv))
            (should (= 1 fi))
            (should (= 1 dr))))
      (delete-file file))))

;;; --- Health score with methodology markers ---

(ert-deftest blueprint-test-health-score/da-validare-penalty ()
  "Each [DA VALIDARE] deducts 1 from health score."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n#+BLUEPRINT_DEPENDS:\n\n[DA VALIDARE]\n[DA VALIDARE]\n\n* Introduction\n\n* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n")
    (blueprint--invalidate-cache)
    (should (= 98 (blueprint-health-score)))))  ; 100 - 2*1

(ert-deftest blueprint-test-health-score/finding-penalty ()
  "Each [FINDING] deducts 2 from health score."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n#+BLUEPRINT_DEPENDS:\n\n[FINDING] anomalia rilevata\n\n* Introduction\n\n* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n")
    (blueprint--invalidate-cache)
    (should (= 98 (blueprint-health-score)))))  ; 100 - 1*2

;;; --- blueprint-list-findings / blueprint-list-unvalidated ---

(ert-deftest blueprint-test-list-findings/creates-buffer ()
  "blueprint-list-findings creates a results buffer."
  (blueprint-test--with-project
    (blueprint-list-findings)
    (should (get-buffer "*Blueprint: Blueprint Findings*"))))

(ert-deftest blueprint-test-list-findings/finds-marker ()
  "[FINDING] in a component file appears in the results buffer."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp" "#+TITLE: comp\n\n[FINDING] discrepanza rilevata nel flusso\n")
    (blueprint-list-findings)
    (with-current-buffer "*Blueprint: Blueprint Findings*"
      (should (string-match-p "discrepanza rilevata" (buffer-string))))))

(ert-deftest blueprint-test-list-unvalidated/finds-marker ()
  "[DA VALIDARE] in a component file appears in the results buffer."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp" "#+TITLE: comp\n\n[DA VALIDARE]\n")
    (blueprint-list-unvalidated)
    (with-current-buffer "*Blueprint: Blueprint Sezioni da validare*"
      (should (string-match-p "DA VALIDARE" (buffer-string))))))

(provide 'blueprint-test-health)
;;; blueprint-test-health.el ends here
