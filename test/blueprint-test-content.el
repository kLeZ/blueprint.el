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

(ert-deftest blueprint-test-glossary/add-has-source-property ()
  "Added term includes a :SOURCE: property."
  (blueprint-test--with-project
    (blueprint-glossary-add "Widget" "A small component" "interview-2024")
    (let ((content (blueprint-test--read-file
                    (expand-file-name "glossary.org" default-directory))))
      (should (string-match-p ":SOURCE: interview-2024" content)))))

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

(ert-deftest blueprint-test-questions/unknown-component-errors ()
  "Adding a question to a non-existent component raises an error."
  (blueprint-test--with-project
    (should-error (blueprint-add-question "ghost" "Does this exist?")
                  :type 'user-error)))

(provide 'blueprint-test-content)
;;; blueprint-test-content.el ends here
