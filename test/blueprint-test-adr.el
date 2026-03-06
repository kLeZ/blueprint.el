;;; blueprint-test-adr.el --- Tests for blueprint-adr.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the consolidated ADR model: a single adr.org file where each
;; ADR is a level-1 heading with STATUS in its PROPERTIES drawer.
;;
;; NOTE: `blueprint-adr-new' calls `find-file', which changes the current
;; buffer and buffer-local `default-directory'.  Always capture the project
;; directory in `proj' BEFORE calling `blueprint-adr-new'.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-adr)

;;; --- Helpers ---

(defun blueprint-test--write-adr-file (content)
  "Write CONTENT to .blueprint/adr.org in the current project."
  (let ((file (expand-file-name ".blueprint/adr.org" default-directory)))
    (with-temp-file file (insert content))
    file))

;;; --- blueprint--adr-next-number ---

(ert-deftest blueprint-test-adr-number/no-adr-file ()
  "Returns 0001 when adr.org does not exist."
  (blueprint-test--with-project
    (should (equal "0001" (blueprint--adr-next-number)))))

(ert-deftest blueprint-test-adr-number/empty-adr-file ()
  "Returns 0001 when adr.org exists but has no ADR headings."
  (blueprint-test--with-project
    (blueprint-test--write-adr-file "#+TITLE: ADRs\n\nSome intro.\n")
    (should (equal "0001" (blueprint--adr-next-number)))))

(ert-deftest blueprint-test-adr-number/sequential ()
  "Increments past the highest existing ADR number."
  (blueprint-test--with-project
    (blueprint-test--write-adr-file
     (concat "* ADR 0001: First\n:PROPERTIES:\n:STATUS: proposed\n:END:\n\n"
             "* ADR 0003: Third\n:PROPERTIES:\n:STATUS: accepted\n:END:\n\n"))
    (should (equal "0004" (blueprint--adr-next-number)))))

(ert-deftest blueprint-test-adr-number/ignores-non-adr-headings ()
  "Headings that do not match the `* ADR NNNN:' format are ignored."
  (blueprint-test--with-project
    (blueprint-test--write-adr-file
     (concat "#+TITLE: ADRs\n\n"
             "* Introduction\n\nSome text.\n\n"
             "* ADR 0002: Real ADR\n:PROPERTIES:\n:STATUS: proposed\n:END:\n\n"))
    (should (equal "0003" (blueprint--adr-next-number)))))

;;; --- blueprint--adr-ensure-file ---

(ert-deftest blueprint-test-adr-ensure/creates-adr-file ()
  "blueprint--adr-ensure-file creates adr.org when absent."
  (blueprint-test--with-project
    (let ((f (blueprint--adr-ensure-file)))
      (should (file-exists-p f))
      (should (string-match-p "adr\\.org$" f)))))

(ert-deftest blueprint-test-adr-ensure/idempotent ()
  "blueprint--adr-ensure-file does not overwrite an existing adr.org."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-adr-file "#+TITLE: My ADRs\n\nManual content.\n")))
      (blueprint--adr-ensure-file)
      (should (string-match-p "Manual content" (blueprint-test--read-file f))))))

;;; --- blueprint-adr-new ---

(ert-deftest blueprint-test-adr-new/creates-adr-org ()
  "blueprint-adr-new creates adr.org when it does not exist."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use PostgreSQL")
      (should (file-exists-p
               (expand-file-name ".blueprint/adr.org" proj))))))

(ert-deftest blueprint-test-adr-new/appends-heading ()
  "blueprint-adr-new appends a level-1 ADR heading to adr.org."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use PostgreSQL")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should (string-match-p "\\* ADR 0001: Use PostgreSQL" content))))))

(ert-deftest blueprint-test-adr-new/has-status-property ()
  "New ADR has STATUS=proposed in its PROPERTIES drawer."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Adopt CQRS")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should (string-match-p ":STATUS: proposed" content))))))

(ert-deftest blueprint-test-adr-new/has-date-property ()
  "New ADR has DATE property with today's year in its PROPERTIES drawer."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use Event Sourcing")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should (string-match-p ":DATE:" content))
        (should (string-match-p (format-time-string "%Y") content))))))

(ert-deftest blueprint-test-adr-new/has-subsections ()
  "New ADR contains Contesto, Decisione, Conseguenze sub-headings."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Some Decision")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should (string-match-p "\\*\\* Contesto" content))
        (should (string-match-p "\\*\\* Decisione" content))
        (should (string-match-p "\\*\\* Conseguenze" content))))))

(ert-deftest blueprint-test-adr-new/sequential-numbering ()
  "Multiple ADRs are numbered sequentially."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "First decision")
      (blueprint-adr-new "Second decision")
      (blueprint-adr-new "Third decision")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should (string-match-p "ADR 0001: First decision" content))
        (should (string-match-p "ADR 0002: Second decision" content))
        (should (string-match-p "ADR 0003: Third decision" content))))))

(ert-deftest blueprint-test-adr-new/all-in-one-file ()
  "Multiple ADRs accumulate in a single adr.org, not separate files."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "First")
      (blueprint-adr-new "Second")
      ;; adr.org lives directly in .blueprint/, not in a subdirectory
      (let ((adr-file (expand-file-name ".blueprint/adr.org" proj)))
        (should (file-exists-p adr-file))
        (let ((content (blueprint-test--read-file adr-file)))
          (should (string-match-p "ADR 0001.*First" content))
          (should (string-match-p "ADR 0002.*Second" content)))))))

(ert-deftest blueprint-test-adr-new/no-unreplaced-placeholders ()
  "adr.org created by blueprint-adr-new contains no unreplaced placeholders."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Some Decision")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/adr.org" proj))))
        (should-not (string-match-p "{{PROJECT}}" content))
        (should-not (string-match-p "{{DATE}}" content))))))

;;; --- blueprint-adr-list ---

(ert-deftest blueprint-test-adr-list/no-file-message ()
  "blueprint-adr-list shows message when adr.org is absent."
  ;; We just verify it does not error; the message is ephemeral.
  (blueprint-test--with-project
    (should (progn (blueprint-adr-list) t))))

(ert-deftest blueprint-test-adr-list/shows-adrs ()
  "blueprint-adr-list displays ADRs found in adr.org."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use PostgreSQL")
      (blueprint-adr-new "Adopt Microservices")
      (blueprint-adr-list)
      (let ((buf (get-buffer "*Blueprint ADRs*")))
        (should buf)
        (with-current-buffer buf
          (let ((content (buffer-string)))
            (should (string-match-p "Use PostgreSQL" content))
            (should (string-match-p "Adopt Microservices" content))
            (should (string-match-p "proposed" content))))))))

(provide 'blueprint-test-adr)
;;; blueprint-test-adr.el ends here
