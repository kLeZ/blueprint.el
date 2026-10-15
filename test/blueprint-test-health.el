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

(ert-deftest blueprint-test-metrics/binary-content-no-crash ()
  "A file with invalid-UTF-8 / binary content does not error; markers
inside otherwise-valid text are still counted (a \"corrupted\" arc42.org
should degrade, not crash the whole health scan)."
  (let ((file (make-temp-file "bp-corrupt-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert "QUESTION unresolved\n")
            (insert (unibyte-string 0 255 254 1 2 3))
            (insert "\nTBD later\n")
            (write-region (point-min) (point-max) file))
          (should (equal '(1 1 0) (blueprint--component-metrics file))))
      (delete-file file))))

(ert-deftest blueprint-test-health-score/dangling-component-no-crash ()
  "blueprint-health-score does not error when a registered component's
directory exists but its arc42.org was deleted after the fact (e.g. by
hand outside Blueprint).  Documents actual behavior: a missing file
contributes zero markers to the score, since detecting a missing
arc42.org is blueprint-lint's job, not blueprint-health-score's."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (delete-file (expand-file-name ".blueprint/components/svc/arc42.org"
                                    default-directory))
    (should (= 100 (blueprint-health-score)))))

;;; --- blueprint-health-score ---

(defun blueprint-test--health-penalty (id)
  "Return the penalty points of component ID in the health stats."
  (nth 1 (assoc id (blueprint--health-component-stats))))

(defun blueprint-test--health-words (id)
  "Return the exported words of component ID in the health stats."
  (nth 2 (assoc id (blueprint--health-component-stats))))

(ert-deftest blueprint-test-health-score/perfect ()
  "A project with no markers scores 100."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean" "#+TITLE: clean\n\n* Introduction\n\nAll good.\n")
    (blueprint--invalidate-cache)
    (should (= 100 (blueprint-health-score)))))

(ert-deftest blueprint-test-health-score/question-penalty ()
  "Each QUESTION weighs 3 penalty points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Open Questions\n\n- QUESTION one\n- QUESTION two\n")
    (should (= 6 (blueprint-test--health-penalty "comp")))
    (should (< (blueprint-health-score) 100))))

(ert-deftest blueprint-test-health-score/tbd-penalty ()
  "Each TBD weighs 2 penalty points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Section\n\nTBD here.\n")
    (should (= 2 (blueprint-test--health-penalty "comp")))))

(ert-deftest blueprint-test-health-score/fixme-penalty ()
  "Each FIXME weighs 4 penalty points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n\n* Section\n\nFIXME urgent.\n")
    (should (= 4 (blueprint-test--health-penalty "comp")))))

(ert-deftest blueprint-test-health-score/multiple-components ()
  "Penalties and words accumulate across all components."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "a" "#+TITLE: a\n\n* S\n\nQUESTION one\n")   ; 3
    (blueprint-test--write-component
     "b" "#+TITLE: b\n\n* S\n\nFIXME one\n")       ; 4
    (let* ((stats (blueprint--health-component-stats))
           (penalty (apply #'+ (mapcar #'cadr stats)))
           (words (apply #'+ (mapcar #'caddr stats))))
      (should (equal '("a" "b") (mapcar #'car stats)))
      (should (= 7 penalty))
      (should (= (blueprint--health-score-from penalty words)
                 (blueprint-health-score))))))

(ert-deftest blueprint-test-health-score/empty-project ()
  "An empty project (no components) scores 100."
  (blueprint-test--with-project
    (should (= 100 (blueprint-health-score)))))

;;; --- Health score formula (PLAN 9.28) ---

(ert-deftest blueprint-test-health-score/formula ()
  "Score is round (100 * U / (U + P)) with U = W / N."
  (let ((blueprint-health-words-per-point 100))
    (should (= 50 (blueprint--health-score-from 1 100)))
    (should (= 75 (blueprint--health-score-from 1 300)))
    (should (= 25 (blueprint--health-score-from 3 100)))
    (should (= 91 (blueprint--health-score-from 1 1000))))
  (let ((blueprint-health-words-per-point 50))
    (should (= 67 (blueprint--health-score-from 1 100))))
  (let ((blueprint-health-words-per-point 100.0))
    (should (= 50 (blueprint--health-score-from 1 100)))))

(ert-deftest blueprint-test-health-score/edge-cases ()
  "No penalty gives 100 (also with no words); penalty with no words gives 0."
  (should (= 100 (blueprint--health-score-from 0 0)))
  (should (= 100 (blueprint--health-score-from 0 5000)))
  (should (= 0 (blueprint--health-score-from 5 0)))
  (should (= 0 (blueprint--health-score-from 1000000 1)))
  (should (= 100 (blueprint--health-score-from 1 100000000))))

(ert-deftest blueprint-test-health-score/size-normalized ()
  "Doubling the document with the same markers per word keeps the score.
The old score subtracted absolute points, so it fell as the document
grew even when the share of open points did not change."
  (let* ((blueprint-health-words-per-point 100)
         (body (concat "* Sezione\n\n"
                       (mapconcat #'identity (make-list 60 "parola") " ")
                       "\nQUESTION aperta e TBD da scrivere.\n"))
         single double)
    (blueprint-test--with-project
      (blueprint-test--write-component "comp" body)
      (setq single (list (blueprint-test--health-penalty "comp")
                         (blueprint-test--health-words "comp")
                         (blueprint-health-score))))
    (blueprint-test--with-project
      (blueprint-test--write-component "comp" (concat body body))
      (setq double (list (blueprint-test--health-penalty "comp")
                         (blueprint-test--health-words "comp")
                         (blueprint-health-score))))
    (should (= (* 2 (nth 0 single)) (nth 0 double)))
    (should (= (* 2 (nth 1 single)) (nth 1 double)))
    (should (< 0 (nth 2 single) 100))
    (should (= (nth 2 single) (nth 2 double)))
    ;; Same check with the growth spread over a second component.
    (blueprint-test--with-project
      (blueprint-test--write-component "a" body)
      (blueprint-test--write-component "b" body)
      (should (= (nth 2 single) (blueprint-health-score))))))

(ert-deftest blueprint-test-health-score/counts-functional-and-infrastructure ()
  "Markers and words of functional.org and infrastructure.org count too."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component
                   "comp" "#+TITLE: comp\n\n* S\n\nQUESTION uno\n"))
           (dir (file-name-directory arc42)))
      (with-temp-file (expand-file-name "functional.org" dir)
        (insert "* F\n\nTBD due tre\n"))
      (with-temp-file (expand-file-name "infrastructure.org" dir)
        (insert "* I\n\nFIXME quattro\n"))
      (should (= 9 (blueprint-test--health-penalty "comp"))) ; 3 + 2 + 4
      (should (= (+ (cdr (blueprint--health-file-stats arc42))
                    (cdr (blueprint--health-file-stats
                          (expand-file-name "functional.org" dir)))
                    (cdr (blueprint--health-file-stats
                          (expand-file-name "infrastructure.org" dir))))
                 (blueprint-test--health-words "comp"))))))

(ert-deftest blueprint-test-health-score/absent-files-ignored ()
  "A component without infrastructure.org counts its other files only."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component
                   "comp" "#+TITLE: comp\n\n* S\n\nQUESTION uno\n"))
           (dir (file-name-directory arc42)))
      (with-temp-file (expand-file-name "functional.org" dir)
        (insert "* F\n\nTBD due\n"))
      (should (equal (list arc42 (expand-file-name "functional.org" dir))
                     (blueprint--component-document-paths "comp")))
      (should (= 5 (blueprint-test--health-penalty "comp"))))))

(ert-deftest blueprint-test-health-score/finding-weighs-zero ()
  "[FINDING] is still counted but does not lower the score."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "comp"
                 "#+TITLE: comp\n\n* Rischi\n\n[FINDING] anomalia rilevata\n")))
      (should (= 1 (nth 1 (blueprint--methodology-metrics file))))
      (should (= 0 (blueprint-test--health-penalty "comp")))
      (should (= 100 (blueprint-health-score))))))

(ert-deftest blueprint-test-health-score/dangling-functional-ignored ()
  "A component whose only file is functional.org does not error."
  (blueprint-test--with-project
    (let ((dir (file-name-directory (blueprint-test--write-component "svc"))))
      (delete-file (expand-file-name "arc42.org" dir))
      (with-temp-file (expand-file-name "functional.org" dir)
        (insert "* F\n\nTBD\n"))
      (should (= 2 (blueprint-test--health-penalty "svc")))
      ;; Two words ("F", "TBD") against 2 points: round (100 * 2 / (2 + 200)) = 1.
      (let ((blueprint-health-words-per-point 100))
        (should (= 2 (blueprint-test--health-words "svc")))
        (should (= 1 (blueprint-health-score)))))))

;;; --- Exported word count ---

(ert-deftest blueprint-test-words/count-exported-text-only ()
  "Words count only outside `blueprint--uncounted-regions'.
Nested regions (verbatim inside a :noexport: subtree) are not
subtracted twice."
  (with-temp-buffer
    (insert "* Intro\n"
            "uno due tre =verbatim= ~code~\n"
            "#+begin_src emacs-lisp\n(setq x 1)\n#+end_src\n"
            "# commento ignorato\n"
            "* Guida :noexport:\n"
            "quattro =cinque= sei\n"
            "** Sotto\nsette\n"
            "#+begin_example\notto\n#+end_example\n"
            "* COMMENT Nota\nnove\n"
            "* Coda\ndieci undici\n")
    (let ((org-inhibit-startup t))
      (delay-mode-hooks (org-mode)))
    ;; Intro uno due tre + Coda dieci undici
    (should (= 7 (blueprint--count-words-outside)))))

(ert-deftest blueprint-test-words/merge-regions ()
  "Overlapping and nested regions merge into disjoint ones."
  (should (equal '((1 . 10) (12 . 20))
                 (blueprint--merge-regions
                  '((1 . 10) (2 . 5) (4 . 8) (12 . 15) (15 . 20))))))

(ert-deftest blueprint-test-words/missing-file ()
  "A missing file contributes no penalty and no words."
  (should (equal '(0 . 0) (blueprint--health-file-stats nil)))
  (should (equal '(0 . 0) (blueprint--health-file-stats
                           "/tmp/this-file-does-not-exist.org"))))

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
  "Each [DA VALIDARE] weighs 1 penalty point."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp"
     "#+TITLE: comp\n#+BLUEPRINT_DEPENDS:\n\n[DA VALIDARE]\n[DA VALIDARE]\n\n* Introduction\n\n* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n")
    (should (= 2 (blueprint-test--health-penalty "comp")))))

(ert-deftest blueprint-test-health-score/da-revisionare-penalty ()
  "Each [DA REVISIONARE] weighs 1 penalty point."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp" "#+TITLE: comp\n\n* S\n\n[DA REVISIONARE] bozza\n")
    (should (= 1 (blueprint-test--health-penalty "comp")))))

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

(ert-deftest blueprint-test-list-findings/ignores-lock-files ()
  "An Emacs lock file (dangling .#file.org symlink) does not break the scan.
Regression: any .org file with unsaved changes in the project made
`blueprint-list-findings' fail with file-missing."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "comp" "#+TITLE: comp\n\n[FINDING] trovato\n")))
      (make-symbolic-link "user@host.1234:1"
                          (expand-file-name ".#arc42.org"
                                            (file-name-directory file)))
      (should (= 1 (length (blueprint--scan-marker-occurrences "[FINDING]")))))))

;;; --- Markers in non-exported text do not count (PLAN 9.22) ---

(defconst blueprint-test--noexport-body
  (concat "#+TITLE: svc\n#+STATUS: [DA VALIDARE]\n\n"
          "* Guida alla compilazione :noexport:\n"
          "Usare =[FINDING]= per le anomalie.\n"
          "| Logging | [FINDING] nessuna rotazione | QUESTION |\n\n"
          "* Introduction\n"
          "Testo reale. [FINDING] vero. TBD\n"
          "Si cita =[DA VALIDARE]= e ~FIXME~ in verbatim/code.\n"
          "#+begin_src org\n[FINDING] esempio QUESTION\n#+end_src\n"
          "#+begin_example\nTBD [DA REVISIONARE]\n#+end_example\n"
          "# commento: FIXME\n"
          "* COMMENT Note interne\n[FINDING] commentato\n"
          "* Interna :riservato:\nQUESTION fuori export\n"
          "* Tail\nuna question minuscola e un tbd minuscolo\n")
  "Component body with markers in exported and non-exported text.")

(ert-deftest blueprint-test-countable/metrics-skip-non-exported ()
  "Only markers in exported, non-verbatim text are counted."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "svc" blueprint-test--noexport-body)))
      ;; QUESTION only in :riservato: (exported: counts), TBD in Introduction.
      (should (equal '(1 1 0) (blueprint--component-metrics file)))
      ;; #+STATUS: keyword counts; the verbatim mention does not.
      (should (equal '(1 1 0) (blueprint--methodology-metrics file))))))

(ert-deftest blueprint-test-countable/exclude-tags-keyword ()
  "Tags listed in #+EXCLUDE_TAGS: are excluded like :noexport:."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "svc" (concat "#+EXCLUDE_TAGS: riservato noexport\n"
                               blueprint-test--noexport-body))))
      (should (equal '(0 1 0) (blueprint--component-metrics file))))))

(ert-deftest blueprint-test-countable/scan-skips-non-exported ()
  "blueprint-list-findings lists only the real finding."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc" blueprint-test--noexport-body)
    (let ((hits (blueprint--scan-marker-occurrences "[FINDING]")))
      (should (= 1 (length hits)))
      (should (string-match-p "vero" (nth 2 (car hits)))))))

(ert-deftest blueprint-test-countable/fresh-template-has-no-findings ()
  "A component fresh from the system templates has no [FINDING].
Regression: the fictional example tables in the :noexport: guides
produced findings and lowered the health score of empty components."
  (blueprint-test--with-project
    (blueprint-add-component "svc")
    (should (null (blueprint--scan-marker-occurrences "[FINDING]")))
    (should (= 0 (nth 1 (blueprint--methodology-metrics
                         (blueprint--component-file "svc")))))))

(ert-deftest blueprint-test-list-unvalidated/finds-marker ()
  "[DA VALIDARE] in a component file appears in the results buffer."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "comp" "#+TITLE: comp\n\n[DA VALIDARE]\n")
    (blueprint-list-unvalidated)
    (with-current-buffer "*Blueprint: Blueprint Sezioni da validare*"
      (should (string-match-p "DA VALIDARE" (buffer-string))))))

;;; --- Health gauge SVG ---

(ert-deftest blueprint-test-health-svg/standalone-document ()
  "The gauge declares the SVG namespace and paints its own background.
Regression: without xmlns librsvg, browsers and LibreOffice do not treat
the file as SVG; with a transparent background the black strokes vanish
on a dark theme."
  (let ((svg (blueprint--health-svg-string 87)))
    (should (string-match-p "xmlns='http://www.w3.org/2000/svg'" svg))
    (should (string-match-p "<rect [^>]*fill='white'" svg))
    (should (string-match-p "Health: 87" svg))
    (with-temp-buffer
      (insert svg)
      (should (eq 'svg (car (libxml-parse-xml-region (point-min) (point-max))))))))

(ert-deftest blueprint-test-health-svg/needle-direction ()
  "Score 0 points the needle left, 100 right, 50 straight up."
  (let ((needle (lambda (score)
                  (let ((svg (blueprint--health-svg-string score)))
                    (string-match "x2='\\([-0-9.]+\\)' y2='\\([-0-9.]+\\)'" svg)
                    (cons (round (string-to-number (match-string 1 svg)))
                          (round (string-to-number (match-string 2 svg))))))))
    (should (equal '(30 . 140) (funcall needle 0)))
    (should (equal '(270 . 140) (funcall needle 100)))
    (should (equal '(150 . 20) (funcall needle 50)))))

(ert-deftest blueprint-test-health-svg/writes-file ()
  "blueprint-health-svg writes health.svg at the project root."
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (out (blueprint-health-svg)))
      (should (string= (expand-file-name "health.svg" proj) out))
      (should (string-match-p "Health: 100" (blueprint-test--read-file out)))
      (when (get-buffer "*Blueprint Health*")
        (kill-buffer "*Blueprint Health*")))))

;;; --- Only the document counts: master.org and its includes (PLAN 9.31) ---

(defun blueprint-test--document-project ()
  "Write a project whose master.org includes component and other files.
Component svc: arc42.org included (QUESTION), functional.org not
included (FIXME).  Other files: master.org (TBD), glossary.org
\([DA VALIDARE]), nfr/risks.org ([DA REVISIONARE], [FINDING]).
notes.org (FIXME FIXME) is not included."
  (blueprint-test--write-component
   "svc" "#+TITLE: svc\n\n* Introduction\n\nText QUESTION here.\n")
  (blueprint-test--write-document
   "svc" "functional.org" "#+TITLE: f\n\n* A\n\nFIXME out of the document.\n")
  (blueprint-test--write-file
   "master.org"
   (concat "#+TITLE: Doc\n\n* Parte 0\n\nPremesse TBD.\n"
           "#+INCLUDE: \"glossary.org\" :minlevel 3\n"
           "* Parte II\n"
           "#+INCLUDE: \".blueprint/components/svc/arc42.org\" :minlevel 3\n"
           "* Parte V\n"
           "#+INCLUDE: \"nfr/risks.org\" :minlevel 2\n"))
  (blueprint-test--write-file "glossary.org" "* Glossario\n\nTermine [DA VALIDARE].\n")
  (blueprint-test--write-file
   "nfr/risks.org" "* Rischi\n\nR-1 [DA REVISIONARE] [FINDING] rischio.\n")
  (blueprint-test--write-file "notes.org" "* Note\n\nFIXME FIXME\n"))

(ert-deftest blueprint-test-health-score/counts-document-only ()
  "The score covers master.org and its includes, nothing else.
Penalty: QUESTION 3 + TBD 2 + [DA VALIDARE] 1 + [DA REVISIONARE] 1;
the FIXME of the non-included functional.org and notes.org do not
count, the parts outside the components do."
  (blueprint-test--with-project
    (blueprint-test--document-project)
    (let ((summary (blueprint--document-health-summary)))
      (should (= 7 (plist-get summary :penalty)))
      (should (= 0 (blueprint--health-marker-count
                    (plist-get summary :counts) "\\<FIXME\\>")))
      (should (= (blueprint-health-score)
                 (blueprint--health-score-from 7 (plist-get summary :words)))))
    ;; The component counts only its included arc42.org.
    (should (= 3 (blueprint-test--health-penalty "svc")))))

(ert-deftest blueprint-test-health-score/rows-add-up-to-document ()
  "Penalty and words of the document rows add up to the health inputs."
  (blueprint-test--with-project
    (blueprint-test--document-project)
    (let ((rows (mapcar #'blueprint--unit-health-summary (blueprint--document-units)))
          (doc (blueprint--document-health-summary)))
      (should (= (plist-get doc :penalty)
                 (apply #'+ (mapcar (lambda (r) (plist-get r :penalty)) rows))))
      (should (= (plist-get doc :words)
                 (apply #'+ (mapcar (lambda (r) (plist-get r :words)) rows)))))))

(ert-deftest blueprint-test-list-unvalidated/document-only ()
  "The marker lists scan the document files only."
  (blueprint-test--with-project
    (blueprint-test--document-project)
    (blueprint-test--write-file "kb/notes.org" "[DA VALIDARE] interno\n")
    (let ((hits (blueprint--scan-marker-occurrences "[DA VALIDARE]")))
      (should (= 1 (length hits)))
      (should (string-suffix-p "glossary.org" (car (car hits)))))))

(provide 'blueprint-test-health)
;;; blueprint-test-health.el ends here
