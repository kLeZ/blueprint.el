;;; blueprint-test-changelog.el --- Tests for blueprint-changelog.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the changelog generation: git log parsing, ADR selection,
;; assembly of CHANGELOG.org, the confirmation on an existing file and
;; an end-to-end run against a real temporary git repository.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-changelog)
(require 'blueprint-adr)

(ert-deftest blueprint-test-changelog/parse-log ()
  "Log lines of the form hash|date|subject parse into entries."
  (let ((entries (blueprint--changelog-parse-log
                  "abc1234|2026-11-01|Primo commit\nbeef567|2026-10-30|Secondo\n")))
    (should (= (length entries) 2))
    (should (equal (car entries) '("abc1234" "2026-11-01" "Primo commit")))
    (should (equal (cadr entries) '("beef567" "2026-10-30" "Secondo")))))

(ert-deftest blueprint-test-changelog/parse-log-ignores-other-lines ()
  "Lines that do not match (git warnings, blank lines) are skipped."
  (should (null (blueprint--changelog-parse-log
                 "warning: qualcosa\n\nnot a log line\n"))))

(ert-deftest blueprint-test-changelog/assembly-groups-by-date ()
  "Entries are grouped under one date heading each, most recent first."
  (let ((content (blueprint--changelog-assembly
                  '(("abc1234" "2026-11-01" "Ultimo")
                    ("beef567" "2026-11-01" "Stesso giorno")
                    ("deadbee" "2026-10-30" "Più vecchio"))
                  '(("0001" "Adozione di PostgreSQL" "2026-10-01"))
                  "Progetto"))
        (buffer nil))
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (setq buffer (buffer-string)))
    (should (string-match-p "^\\*\\* 2026-11-01\n\n- abc1234 Ultimo\n- beef567 Stesso giorno\n\n\\*\\* 2026-10-30\n\n- deadbee" buffer))
    (should (string-match-p "^\\* Decisioni architetturali (ADR accettate)\n\n- ADR 0001 (2026-10-01): Adozione di PostgreSQL" buffer))
    (should (string-match-p "CHANGELOG — Progetto" buffer))))

(ert-deftest blueprint-test-changelog/assembly-empty-log ()
  "Without commits the cronology says so instead of being empty."
  (let ((content (blueprint--changelog-assembly nil nil "P")))
    (should (string-match-p "Nessun commit registrato" content))
    (should (string-match-p "Nessuna ADR accettata" content))))

(ert-deftest blueprint-test-changelog/adr-accepted-only ()
  "Only the ADRs with :STATUS: accepted are listed, in file order; the
ones the export leaves out (:noexport:, COMMENT) are not."
  (blueprint-test--with-project
    (blueprint-test--write-file
     ".blueprint/adr.org"
     (concat "* ADR 0001: Primo\n:PROPERTIES:\n:STATUS: accepted\n:DATE: 2026-10-01\n:END:\n\n"
             "* ADR 0002: Secondo\n:PROPERTIES:\n:STATUS: proposed\n:DATE: 2026-10-02\n:END:\n\n"
             "* ADR 0003: Terzo\n:PROPERTIES:\n:STATUS: accepted\n:DATE: 2026-10-03\n:END:\n\n"
             "* ADR 0004: Esempio :noexport:\n:PROPERTIES:\n:STATUS: accepted\n:DATE: 2026-10-04\n:END:\n\n"
             "* COMMENT ADR 0005: Bozza\n:PROPERTIES:\n:STATUS: accepted\n:DATE: 2026-10-05\n:END:\n\n"))
    (should (equal (blueprint--changelog-adr-accepted)
                   '(("0001" "Primo" "2026-10-01")
                     ("0003" "Terzo" "2026-10-03"))))))

(ert-deftest blueprint-test-changelog/template-example-adr-not-listed ()
  "The accepted example ADR of the adr.org template lives in a
:noexport: heading: a fresh project has no accepted ADR."
  (blueprint-test--with-project
    (blueprint--adr-ensure-file)
    (should (file-exists-p (blueprint--data-path "adr.org")))
    (should (null (blueprint--changelog-adr-accepted)))))

(ert-deftest blueprint-test-changelog/generate-writes-file ()
  "The command writes CHANGELOG.org with the git history and the ADRs."
  (blueprint-test--with-project
    (blueprint-test--write-file
     ".blueprint/adr.org"
     "* ADR 0001: Scelta\n:PROPERTIES:\n:STATUS: accepted\n:DATE: 2026-10-01\n:END:\n\n")
    (cl-letf (((symbol-function 'blueprint--changelog-git-log)
               (lambda (&optional _since)
                 '(("abc1234" "2026-11-01" "Un commit")))))
      (should (stringp (blueprint-changelog-generate))))
    (let ((content (blueprint-test--read-file
                    (expand-file-name "CHANGELOG.org" default-directory))))
      (should (string-match-p "- abc1234 Un commit" content))
      (should (string-match-p "- ADR 0001 (2026-10-01): Scelta" content)))))

(ert-deftest blueprint-test-changelog/generate-asks-before-overwriting ()
  "With CHANGELOG.org already there, a refused confirmation leaves the
file untouched."
  (blueprint-test--with-project
    (blueprint-test--write-file "CHANGELOG.org" "MANUALE\n")
    (cl-letf (((symbol-function 'blueprint--changelog-git-log)
               (lambda (&optional _since) '(("abc1234" "2026-11-01" "X"))))
              ((symbol-function 'yes-or-no-p) (lambda (_) nil)))
      (should-error (blueprint-changelog-generate) :type 'user-error))
    (should (string= "MANUALE\n"
                     (blueprint-test--read-file
                      (expand-file-name "CHANGELOG.org" default-directory))))))

(ert-deftest blueprint-test-changelog/generate-from-a-real-repo ()
  "End-to-end: a temporary git repository feeds the cronology."
  (blueprint-test--with-project
    (let* ((root default-directory)
           (git (lambda (&rest args)
                  (apply #'call-process "git" nil nil nil args))))
      (funcall git "init" "-q")
      (funcall git "config" "user.email" "test@example.com")
      (funcall git "config" "user.name" "Test")
      (with-temp-file (expand-file-name "file.txt" root) (insert "x\n"))
      (funcall git "add" "file.txt")
      (funcall git "commit" "-q" "-m" "Commit di prova")
      (blueprint-changelog-generate)
      (let ((content (blueprint-test--read-file
                      (expand-file-name "CHANGELOG.org" root))))
        (should (string-match-p "Commit di prova" content))
        (should (string-match-p (concat "^\\*\\* "
                                        (format-time-string "%Y-%m-%d"))
                                content))))))

(provide 'blueprint-test-changelog)
;;; blueprint-test-changelog.el ends here
