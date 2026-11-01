;;; blueprint-test-agenda.el --- Tests for blueprint-agenda.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the org-agenda integration: entry generation from the
;; document markers, stable IDs, and preservation of DEADLINE,
;; SCHEDULED and TODO/DONE state across refreshes.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-agenda)
(require 'blueprint-sync)

(defun blueprint-test-agenda--write-project ()
  "Fixture project whose document holds one QUESTION and one FIXME,
with all the lint-expected headings so no warning noise appears."
  (blueprint-test--write-file
   "master.org"
   (concat "#+TITLE: Doc\n\n* Parte 0\n\nIntroduzione.\n\n"
           "# @@blueprint-sync-start@@\n"
           "# @@blueprint-sync-end@@\n\n"
           "# @@blueprint-sync-functional-start@@\n"
           "# @@blueprint-sync-functional-end@@\n\n"
           "# @@blueprint-sync-infra-start@@\n"
           "# @@blueprint-sync-infra-end@@\n"))
  (blueprint-test--write-component
   "alpha"
   (concat "#+TITLE: alpha\n\n* Introduction\n\n"
           "Text with QUESTION one.\n\n"
           "* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n"
           "* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n"
           "* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n"))
  (blueprint-test--write-component
   "beta"
   (concat "#+TITLE: beta\n\n* Introduction\n\n"
           "Clean text with a FIXME here.\n\n"
           "* Context and Scope\n\n* Constraints\n\n* Solution Strategy\n\n"
           "* Building Blocks\n\n* Runtime Behavior\n\n* Deployment\n\n"
           "* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n"))
  (let ((blueprint-history-on-sync nil))
    (blueprint-sync)))

(defun blueprint-test-agenda--content ()
  "Return the contents of the generated agenda file."
  (blueprint-test--read-file (blueprint--agenda-file)))

(ert-deftest blueprint-test-agenda/refresh-writes-todo-entries ()
  "Every QUESTION and FIXME marker of the document becomes a TODO
entry, with component, stable ID and origin link."
  (blueprint-test--with-project
    (blueprint-test-agenda--write-project)
    (let ((file (blueprint-agenda-refresh)))
      (should (string= file (blueprint--agenda-file)))
      (should (file-exists-p file))
      (let ((content (blueprint-test-agenda--content)))
        (should (string-match-p "^\\*\\* TODO QUESTION: alpha — .*QUESTION one" content))
        (should (string-match-p "^\\*\\* TODO FIXME: beta — .*FIXME here" content))
        (should (string-match-p ":BLUEPRINT_MARKER: QUESTION" content))
        (should (string-match-p ":ID: [0-9a-f]\\{10\\}" content))
        (should (string-match-p ":ORIGIN: .*arc42.org" content))))))

(ert-deftest blueprint-test-agenda/ids-are-stable-across-refreshes ()
  "The ID of an entry does not change when the file is regenerated."
  (blueprint-test--with-project
    (blueprint-test-agenda--write-project)
    (blueprint-agenda-refresh)
    (let ((id-1 (progn (string-match ":ID: \\([0-9a-f]+\\)"
                                     (blueprint-test-agenda--content))
                       (match-string 1 (blueprint-test-agenda--content)))))
      (blueprint-agenda-refresh)
      (string-match ":ID: \\([0-9a-f]+\\)" (blueprint-test-agenda--content))
      (should (string= id-1
                       (match-string 1 (blueprint-test-agenda--content)))))))

(ert-deftest blueprint-test-agenda/deadline-preserved-across-refresh ()
  "A DEADLINE set by hand on an entry survives the refresh."
  (blueprint-test--with-project
    (blueprint-test-agenda--write-project)
    (blueprint-agenda-refresh)
    (let ((agenda (blueprint--agenda-file)))
      ;; Add a deadline to the first entry by rewriting the file.
      (let ((content (blueprint-test--read-file agenda)))
        (with-temp-file agenda
          (insert (replace-regexp-in-string
                   "\\(^\\*\\* TODO QUESTION: alpha[^\n]*\n\\)"
                   "\\1DEADLINE: <2026-12-24 ven>\n"
                   content))))
      (blueprint-agenda-refresh)
      (let ((content (blueprint-test-agenda--content)))
        (should (string-match-p "DEADLINE: <2026-12-24" content))
        ;; The entry itself is still there.
        (should (string-match-p "QUESTION: alpha" content))))))

(ert-deftest blueprint-test-agenda/done-state-preserved-across-refresh ()
  "An entry marked DONE by hand stays DONE after the refresh."
  (blueprint-test--with-project
    (blueprint-test-agenda--write-project)
    (blueprint-agenda-refresh)
    (let ((agenda (blueprint--agenda-file))
          (content (blueprint-test-agenda--content)))
      (with-temp-file agenda
        (insert (replace-regexp-in-string
                 "\\(\\*\\* \\)TODO \\(FIXME: beta\\)"
                 "\\1DONE \\2"
                 content)))
      (blueprint-agenda-refresh)
      (should (string-match-p "^\\*\\* DONE FIXME: beta"
                              (blueprint-test-agenda--content)))
      (should-not (string-match-p "^\\*\\* TODO FIXME: beta"
                                  (blueprint-test-agenda--content))))))

(ert-deftest blueprint-test-agenda/refresh-without-markers-writes-skeleton ()
  "With no markers in the document the agenda file is just the header."
  (blueprint-test--with-project
    (blueprint-test--write-file
     "master.org"
     (concat "#+TITLE: Doc\n\n* Parte 0\n\nPulito.\n\n"
             "# @@blueprint-sync-start@@\n"
             "# @@blueprint-sync-end@@\n\n"
             "# @@blueprint-sync-functional-start@@\n"
             "# @@blueprint-sync-functional-end@@\n\n"
             "# @@blueprint-sync-infra-start@@\n"
             "# @@blueprint-sync-infra-end@@\n"))
    (blueprint-agenda-refresh)
    (let ((content (blueprint-test-agenda--content)))
      (should (string-match-p "#\\+TITLE:" content))
      (should-not (string-match-p "^\\*\\* " content)))))

(ert-deftest blueprint-test-agenda/entries-skip-answered-questions ()
  "ANSWERED rows are history: they do not become agenda entries."
  (blueprint-test--with-project
    (blueprint-test-agenda--write-project)
    (let ((arc (expand-file-name ".blueprint/components/alpha/arc42.org"
                                 default-directory)))
      (append-to-file "\n- ANSWERED [2026-11-01] già risolta [FONTE: x]\n" nil arc)
      (blueprint--invalidate-cache)
      (blueprint-agenda-refresh)
      (let ((content (blueprint-test-agenda--content)))
        (should (= 2 (with-temp-buffer
                       (insert content)
                       (goto-char (point-min))
                       (count-matches "^\\*\\* TODO "))))
        (should-not (string-match-p "già risolta" content))))))

(provide 'blueprint-test-agenda)
;;; blueprint-test-agenda.el ends here
