;;; blueprint-test-content.el --- Tests for glossary, references and questions  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for blueprint-glossary.el, blueprint-references.el, and
;; blueprint-questions.el content management commands.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-glossary)
(require 'blueprint-references)
(require 'blueprint-questions)

;;; --- Glossary ---

(ert-deftest blueprint-test-glossary/add-creates-file ()
  "blueprint-glossary-add creates the glossary file if absent.
At the project root, from the real glossary.org template -- the same
file `blueprint-init' would have created, and the same file
`master.org' includes.  Not under `.blueprint/', which holds
per-component and per-ADR data, not project-level deliverables."
  (blueprint-test--with-project
    (blueprint-glossary-add "API" "Application Programming Interface" "team-docs")
    (should (file-exists-p
             (expand-file-name "glossary.org" default-directory)))
    (should-not (file-exists-p
                (expand-file-name ".blueprint/glossary.org" default-directory)))
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      ;; Confirms the real template was used, not a bare stub.
      (should (string-match-p "Termini di dominio" content)))))

(ert-deftest blueprint-test-glossary/add-term-present ()
  "Added term appears in the glossary file."
  (blueprint-test--with-project
    (blueprint-glossary-add "Cache" "Temporary storage layer" "arch-review")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      (should (string-match-p "Cache" content))
      (should (string-match-p "Temporary storage layer" content))
      (should (string-match-p "arch-review" content)))))

(ert-deftest blueprint-test-glossary/add-multiple-terms ()
  "Multiple terms can be added to the same glossary file."
  (blueprint-test--with-project
    (blueprint-glossary-add "Term-A" "Definition A" "source-a")
    (blueprint-glossary-add "Term-B" "Definition B" "source-b")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      (should (string-match-p "Term-A" content))
      (should (string-match-p "Term-B" content)))))

(ert-deftest blueprint-test-glossary/add-has-source-line ()
  "Added term uses the template format: a /Fonte: .../ line, no drawer.
The old :SOURCE: drawer format is still readable (see the lookup
tests) but new entries follow the glossary template itself."
  (blueprint-test--with-project
    (blueprint-glossary-add "Widget" "A small component" "interview-2024")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      (should (string-match-p "/Fonte: interview-2024/" content))
      (should-not (string-match-p ":SOURCE:" content)))))

(ert-deftest blueprint-test-glossary/add-routes-to-chosen-section ()
  "An explicit section routes the level-2 entry under that heading."
  (blueprint-test--with-project
    (blueprint-glossary-add
     "SAG" "Slowly Applicable Granularity" "team"
     "Termini tecnici con uso specifico")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      ;; The entry sits after the "Termini tecnici" heading and before
      ;; the "Acronimi" one.
      (should (string-match-p
               "^\\* Termini tecnici con uso specifico\n\\(?:.*\n\\)*\\*\\* SAG"
               content))
      (should (string-match-p
               "^\\*\\* SAG\n/Fonte: team/\nSlowly Applicable Granularity"
               content)))))

(ert-deftest blueprint-test-glossary/add-defaults-to-first-section ()
  "Without an explicit section the term goes into the first one."
  (blueprint-test--with-project
    (blueprint-glossary-add "Cache" "Temporary storage" "review")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      (should (string-match-p
               "^\\* Termini di dominio\n\\(?:.*\n\\)*\\*\\* Cache" content)))))

(ert-deftest blueprint-test-glossary/add-unknown-section-errors ()
  "An unknown section is an error, not a silent append."
  (blueprint-test--with-project
    (should-error (blueprint-glossary-add
                   "T" "D" "S" "Sezione inesistente")
                  :type 'user-error)))

(ert-deftest blueprint-test-glossary/lookup-finds-routed-term ()
  "Lookup finds a level-2 entry added by blueprint-glossary-add and
shows the definition with the Fonte line."
  (blueprint-test--with-project
    (blueprint-glossary-add "Microservice" "Small independent service" "docs")
    (let ((msg ""))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
        (blueprint-glossary-lookup "Microservice"))
      (should (string-match-p "Small independent service" msg))
      (should (string-match-p "/Fonte: docs/" msg)))))

(ert-deftest blueprint-test-glossary/lookup-finds-legacy-entry ()
  "Lookup still finds a legacy level-1 entry with a :PROPERTIES: drawer,
and hides the drawer lines from the message."
  (blueprint-test--with-project
    (blueprint-test--write-file
     "glossary.org"
     (concat "* Termini di dominio\n\n"
             "* LegacyTerm\n:PROPERTIES:\n:SOURCE: old-source\n:END:\n"
             "Old definition\n"))
    (let ((msg ""))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
        (blueprint-glossary-lookup "LegacyTerm"))
      (should (string-match-p "Old definition" msg))
      (should-not (string-match-p ":PROPERTIES:" msg))
      (should-not (string-match-p ":SOURCE:" msg)))))

(ert-deftest blueprint-test-glossary/lookup-ignores-guide-examples ()
  "Terms that exist only inside the :noexport: guide are not found."
  (blueprint-test--with-project
    (blueprint-test--write-file
     "glossary.org"
     (concat "* Guida alla compilazione :noexport:\n\n"
             "** FalsoTermine\n\nDefinizione d'esempio.\n\n"
             "* Termini di dominio\n\n** TermineReale\n\nDefinizione reale\n"))
    (let ((msg ""))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
        (blueprint-glossary-lookup "FalsoTermine")
        (should (string-match-p "not found" msg))
        (setq msg "")
        (blueprint-glossary-lookup "TermineReale")
        (should (string-match-p "Definizione reale" msg))))))

(ert-deftest blueprint-test-glossary/lookup-found ()
  "A term that exists in the glossary is found by lookup."
  (blueprint-test--with-project
    (blueprint-glossary-add "Microservice" "Small independent service" "docs")
    ;; lookup calls `message'; we verify it doesn't error
    (should (progn (blueprint-glossary-lookup "Microservice") t))))

(ert-deftest blueprint-test-glossary/lookup-not-found ()
  "Lookup of an absent term does not error."
  (blueprint-test--with-project
    (blueprint-glossary-add "Present" "Here" "src")
    (should (progn (blueprint-glossary-lookup "Absent") t))))

;;; --- References ---

(ert-deftest blueprint-test-references/add-creates-file ()
  "blueprint-reference-add creates the references file if absent.
At the project root, from the real references.org template -- the
same file `blueprint-init' would have created, and the same file
`master.org' includes.  Not under `.blueprint/', which holds
per-component and per-ADR data, not project-level deliverables."
  (blueprint-test--with-project
    (blueprint-reference-add "Design Doc v1" "document" "Main design document")
    (should (file-exists-p
             (expand-file-name "references.org" default-directory)))
    (should-not (file-exists-p
                (expand-file-name ".blueprint/references.org" default-directory)))
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      ;; Confirms the real template was used, not a bare stub.
      (should (string-match-p "references-documents" content)))))

(ert-deftest blueprint-test-references/interview-routes-to-interviste ()
  "A type=interview reference becomes a row in the Interviste table."
  (blueprint-test--with-project
    (blueprint-reference-add "Marco Bianchi" "interview" "Key insights")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p "| I-01 | Marco Bianchi | \\[DA VALIDARE\\] .*Key insights" content)))))

(ert-deftest blueprint-test-references/document-routes-to-documenti ()
  "A non-interview type reference becomes a row in the Documenti table,
with TYPE surfacing as that table's own \"Tipo\" column."
  (blueprint-test--with-project
    (blueprint-reference-add "System Spec" "monitoring" "Spec notes")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p "| D-01 | System Spec | \\[DA VALIDARE\\] .*monitoring.*Spec notes" content)))))

(ert-deftest blueprint-test-references/row-has-todays-date ()
  "Added reference row includes today's date."
  (blueprint-test--with-project
    (blueprint-reference-add "Design Doc" "document" "Notes")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p (format-time-string "%Y-%m-%d") content)))))

(ert-deftest blueprint-test-references/ids-auto-increment-per-section ()
  "IDs auto-increment independently per section (D-NN vs I-NN)."
  (blueprint-test--with-project
    (blueprint-reference-add "Doc A" "document" "n1")
    (blueprint-reference-add "Doc B" "codebase" "n2")
    (blueprint-reference-add "Interview A" "interview" "n3")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p "| D-01 | Doc A" content))
      (should (string-match-p "| D-02 | Doc B" content))
      (should (string-match-p "| I-01 | Interview A" content)))))

(ert-deftest blueprint-test-references/ids-ignore-guide-examples ()
  "Numbering starts at -01 even though the :noexport: guide already
shows D-01/D-02/I-01/I-02 as worked examples -- regression test for
the same class of bug `blueprint--nfr-next-risk-id' had (see its
docstring): a whole-file ID scan with no section boundary mistakes
guide examples for real entries and skips ahead."
  (blueprint-test--with-project
    (blueprint-reference-add "Real document" "document" "notes")
    (blueprint-reference-add "Real interview" "interview" "notes")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p "| D-01 | Real document" content))
      (should (string-match-p "| I-01 | Real interview" content)))))

(ert-deftest blueprint-test-references/add-multiple ()
  "Multiple references accumulate in the same file."
  (blueprint-test--with-project
    (blueprint-reference-add "Ref-1" "document" "Notes 1")
    (blueprint-reference-add "Ref-2" "interview" "Notes 2")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "references.org" default-directory))))
      (should (string-match-p "Ref-1" content))
      (should (string-match-p "Ref-2" content)))))

;;; --- Questions ---

(ert-deftest blueprint-test-questions/add-to-component ()
  "blueprint-add-question inserts a QUESTION marker into the component file."
  (blueprint-test--with-project
    (blueprint-test--write-component "mycomp")
    (blueprint-add-question "mycomp" "Who owns the retry logic?")
    (let ((content (blueprint-test--read-file
                    (blueprint--component-file "mycomp"))))
      (should (string-match-p "QUESTION" content))
      (should (string-match-p "retry logic" content)))))

(ert-deftest blueprint-test-questions/add-creates-section-if-missing ()
  "A QUESTION is added even if the Open Questions heading is absent."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "noq"
     "#+TITLE: noq\n\n* Introduction\n\nSome text.\n")
    (blueprint-add-question "noq" "Where is the API gateway?")
    (let ((content (blueprint-test--read-file (blueprint--component-file "noq"))))
      (should (string-match-p "QUESTION" content))
      (should (string-match-p "API gateway" content)))))

(ert-deftest blueprint-test-questions/multiple-questions ()
  "Multiple questions can be added to the same component."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-add-question "svc" "Question one")
    (blueprint-add-question "svc" "Question two")
    (let ((content (blueprint-test--read-file (blueprint--component-file "svc"))))
      (should (string-match-p "Question one" content))
      (should (string-match-p "Question two" content)))))

(ert-deftest blueprint-test-questions/preserves-blank-line-before-next-heading ()
  "Adding a question keeps the next heading separated by a blank line,
even when the Open Questions heading itself carries a TODO keyword
and a tag."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "mycomp"
     (concat "#+TITLE: mycomp\n\n"
             "* TODO Open Questions :draft:\n\n"
             "- QUESTION existing one\n\n"
             "* DONE Building Blocks :arch:\n\n"
             "Some content that must survive untouched.\n"))
    (blueprint-add-question "mycomp" "New question here")
    (let ((content (blueprint-test--read-file
                    (blueprint--component-file "mycomp"))))
      (should (string-match-p "New question here" content))
      (should-not (string-match-p "New question here\n\\* DONE" content))
      (should (string-match-p "must survive untouched" content)))))

(ert-deftest blueprint-test-questions/list-skips-noexport ()
  "Questions inside a :noexport: subtree are not listed."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" (concat "#+TITLE: svc\n\n* Guida :noexport:\n- QUESTION esempio\n\n"
                   "* Open Questions\n- QUESTION vera\n"))
    (let ((buffers-before (buffer-list)))
      (unwind-protect
          (progn
            (blueprint-list-questions)
            (with-current-buffer "*Blueprint Questions*"
              (should (= 1 (length tabulated-list-entries)))
              (should (string= "vera"
                               (aref (cadr (car tabulated-list-entries)) 1)))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf)))))))

(ert-deftest blueprint-test-questions/list-reads-all-documents ()
  "Questions in functional.org and infrastructure.org are listed too.
Column 1 keeps the question, column 4 names the document; RET opens
the document at the question's line."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc" "#+TITLE: svc\n\n* Open Questions\n")
    (let ((func (blueprint-test--write-document
                 "svc" "functional.org"
                 "#+TITLE: f\n\n* Area\n\n- QUESTION funzionale\n"))
          (buffers-before (buffer-list)))
      (blueprint-test--write-document
       "svc" "infrastructure.org"
       "#+TITLE: i\n\n* Server\n\n- QUESTION infrastruttura\n")
      (unwind-protect
          (progn
            (blueprint-list-questions)
            (with-current-buffer "*Blueprint Questions*"
              (should (eq major-mode 'blueprint-questions-mode))
              (should (equal (mapcar (lambda (e) (list (aref (cadr e) 1)
                                                       (aref (cadr e) 4)))
                                     tabulated-list-entries)
                             '(("funzionale" "functional.org")
                               ("infrastruttura" "infrastructure.org"))))
              (cl-letf (((symbol-function 'tabulated-list-get-id)
                         (lambda () (car (car tabulated-list-entries)))))
                (blueprint-questions-visit)
                (should (equal (buffer-file-name) func))
                (should (looking-at "- QUESTION funzionale")))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf)))))))

(ert-deftest blueprint-test-questions/list-matches-dashboard-count ()
  "The question list counts exactly what the dashboard QUESTION column
counts: every QUESTION marker in exported text of the documents
master.org includes, list items and prose alike; markers outside the
document are not listed."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" (concat "#+TITLE: svc\n\n* Introduction\n\n"
                   "Prose mentioning a QUESTION in the text.\n\n"
                   "* Open Questions\n- QUESTION elenco\n"))
    (blueprint-test--write-document
     "svc" "functional.org"
     "#+TITLE: f\n\n* Area\n\n- QUESTION non inclusa\n")
    (blueprint-test--write-file
     "master.org"
     (concat "#+TITLE: Doc\n\n* Parte 0\n\nIntro.\n\n"
             "# @@blueprint-sync-start@@\n"
             "#+INCLUDE: \".blueprint/components/svc/arc42.org\" :minlevel 3\n"
             "# @@blueprint-sync-end@@\n"))
    (let ((buffers-before (buffer-list)))
      (unwind-protect
          (progn
            (blueprint-list-questions)
            (with-current-buffer "*Blueprint Questions*"
              ;; Two entries: the list item and the prose marker.
              (should (= 2 (length tabulated-list-entries)))
              (should (equal (mapcar (lambda (e) (aref (cadr e) 1))
                                     tabulated-list-entries)
                             '("Prose mentioning a QUESTION in the text."
                               "elenco"))))
            ;; The dashboard QUESTION column agrees.
            (let ((summary (blueprint--unit-health-summary
                            (car (blueprint--document-units)))))
              (should (= 2 (blueprint--health-marker-count
                            (plist-get summary :counts) "\\<QUESTION\\>")))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf)))))))

(ert-deftest blueprint-test-questions/unknown-component-errors ()
  "Adding a question to a non-existent component raises an error."
  (blueprint-test--with-project
    (should-error (blueprint-add-question "ghost" "Does this exist?")
                  :type 'user-error)))

;;; --- Extended question format (9.12): tag, state, fonte ---

(ert-deftest blueprint-test-questions/add-with-tag-writes-metadata ()
  "A tag lands on the row as [TAG: ...]; without a tag the row is
exactly the one of older versions."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-add-question "svc" "With tag" "integrazione")
    (blueprint-add-question "svc" "Without tag")
    (let ((content (blueprint-test--read-file
                    (blueprint--component-file "svc"))))
      (should (string-match-p "^- QUESTION With tag \\[TAG: integrazione\\]$" content))
      (should (string-match-p "^- QUESTION Without tag$" content)))))

(ert-deftest blueprint-test-questions/answer-rewrites-row-with-fonte ()
  "Answering rewrites the row: ANSWERED token, date, kept tag, fonte."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-add-question "svc" "Chi usa il servizio?" "integrazione")
    (let* ((file (blueprint--component-file "svc"))
           (line (with-temp-buffer
                   (insert-file-contents file)
                   (goto-char (point-min))
                   (re-search-forward "^- QUESTION")
                   (line-number-at-pos))))
      (blueprint-answer-question (list "svc" file line) "referente BSP")
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p
                 (concat "^- ANSWERED \\[" (format-time-string "%Y-%m-%d")
                         "\\] Chi usa il servizio\\? \\[TAG: integrazione\\]"
                         " \\[FONTE: referente BSP\\]$")
                 content))))))

(ert-deftest blueprint-test-questions/answer-stops-counting ()
  "An answered question is not an open point anymore: health, dashboard
and question list agree."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-add-question "svc" "Domanda aperta")
    (let* ((file (blueprint--component-file "svc"))
           (line (with-temp-buffer
                   (insert-file-contents file)
                   (goto-char (point-min))
                   (re-search-forward "^- QUESTION")
                   (line-number-at-pos)))
           (before (blueprint-health-score)))
      (blueprint-answer-question (list "svc" file line) "fonte")
      (should (> (blueprint-health-score) before))
      ;; The list shows the row as answered.
      (let ((entries (blueprint--question-entries)))
        (should (= (length entries) 1))
        (should (string= (aref (cadr (car entries)) 3) "answered")))
      ;; The dashboard QUESTION column is back to zero.
      (let* ((blueprint-dashboard-focus nil)
             (fields (cadr (assoc "svc" (blueprint--dashboard-entries)))))
        (should (equal (aref fields 5) "0"))))))

(ert-deftest blueprint-test-questions/list-shows-tag-state-document ()
  "The list carries Tag and State columns; legacy rows (no metadata)
are open with an empty tag."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-add-question "svc" "Con tag" "integrazione")
    (blueprint-add-question "svc" "Senza tag")
    (let ((buffers-before (buffer-list)))
      (unwind-protect
          (progn
            (blueprint-list-questions)
            (with-current-buffer "*Blueprint Questions*"
              (should (equal (mapcar (lambda (e) (list (aref (cadr e) 1)
                                                       (aref (cadr e) 2)
                                                       (aref (cadr e) 3)))
                                     tabulated-list-entries)
                             '(("Con tag" "integrazione" "open")
                               ("Senza tag" "" "open"))))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf)))))))

(ert-deftest blueprint-test-questions/list-filters-by-tag-and-state ()
  "The tag filter (t) and the state filter (s) restrict the list."
  (let ((blueprint-questions-filter-tag nil)
        (blueprint-questions-filter-state nil))
    (blueprint-test--with-project
      (blueprint-test--write-component "svc")
      (blueprint-add-question "svc" "Domanda integrazione" "integrazione")
      (blueprint-add-question "svc" "Domanda glossario" "glossario")
    (let ((buffers-before (buffer-list)))
      (unwind-protect
          (progn
            ;; Tag filter via completing-read.
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "glossario")))
              (blueprint-questions-filter-tag "glossario"))
            (with-current-buffer "*Blueprint Questions*"
              (should (equal (mapcar (lambda (e) (aref (cadr e) 1))
                                     tabulated-list-entries)
                             '("Domanda glossario")))
              (should (string-match-p "tag: glossario" (or mode-line-process ""))))
            ;; State filter: open only (nothing answered here, list stays).
            (blueprint-questions-filter-state)
            (with-current-buffer "*Blueprint Questions*"
              (should (= 1 (length tabulated-list-entries))))
            ;; Clear the tag filter, answer one question, filter answered.
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "all")))
              (blueprint-questions-filter-tag "all"))
            (let* ((file (blueprint--component-file "svc"))
                   (line (with-temp-buffer
                           (insert-file-contents file)
                           (goto-char (point-min))
                           (re-search-forward "^- QUESTION")
                           (line-number-at-pos))))
              (blueprint-answer-question (list "svc" file line) "fonte"))
            (blueprint-questions-filter-state)
            (with-current-buffer "*Blueprint Questions*"
              (should (= 1 (length tabulated-list-entries)))
              (should (equal (aref (cadr (car tabulated-list-entries)) 3)
                             "answered"))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf))))))))

(provide 'blueprint-test-content)
;;; blueprint-test-content.el ends here
