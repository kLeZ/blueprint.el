;;; blueprint-test-adr.el --- Tests for blueprint-adr.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for ADR creation, numbering, and listing.
;; NOTE: `blueprint-adr-new' calls `find-file', which changes the current
;; buffer and buffer-local `default-directory'.  Always capture the project
;; directory in a local variable BEFORE calling `blueprint-adr-new'.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-adr)

;;; --- blueprint--adr-next-number ---

(ert-deftest blueprint-test-adr-number/empty-dir ()
  "First ADR in an empty directory is numbered 0001."
  (blueprint-test--with-project
    (should (equal "0001" (blueprint--adr-next-number)))))

(ert-deftest blueprint-test-adr-number/sequential ()
  "Next number increments past the highest existing ADR."
  (blueprint-test--with-project
    (let ((adr-dir (expand-file-name ".blueprint/adr" default-directory)))
      (with-temp-file (expand-file-name "0001-first.org" adr-dir) (insert ""))
      (with-temp-file (expand-file-name "0003-third.org" adr-dir) (insert ""))
      (should (equal "0004" (blueprint--adr-next-number))))))

(ert-deftest blueprint-test-adr-number/ignores-non-adr-files ()
  "Non-ADR files in the directory are ignored when computing the next number."
  (blueprint-test--with-project
    (let ((adr-dir (expand-file-name ".blueprint/adr" default-directory)))
      (with-temp-file (expand-file-name "README.org" adr-dir) (insert ""))
      (with-temp-file (expand-file-name "notes.txt" adr-dir) (insert ""))
      (should (equal "0001" (blueprint--adr-next-number))))))

;;; --- blueprint-adr-new ---

(ert-deftest blueprint-test-adr-new/creates-file ()
  "blueprint-adr-new creates a file in .blueprint/adr/."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use PostgreSQL")
      (let ((adr-dir (expand-file-name ".blueprint/adr" proj)))
        (let ((files (directory-files adr-dir nil "^[0-9]\\{4\\}-.*\\.org$")))
          (should (= 1 (length files))))))))

(ert-deftest blueprint-test-adr-new/correct-filename ()
  "ADR filename has the correct number prefix and slugified title."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Use Event Sourcing")
      (let ((adr-dir (expand-file-name ".blueprint/adr" proj)))
        (let ((files (directory-files adr-dir nil "^[0-9]\\{4\\}-.*\\.org$")))
          (should (string-match-p "^0001-" (car files)))
          (should (string-match-p "event" (car files))))))))

(ert-deftest blueprint-test-adr-new/replaces-placeholders ()
  "Template placeholders {{NUMBER}}, {{TITLE}}, {{DATE}} are replaced."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Adopt Microservices")
      (let* ((adr-dir (expand-file-name ".blueprint/adr" proj))
             (files (directory-files adr-dir t "^[0-9]\\{4\\}-.*\\.org$"))
             (content (blueprint-test--read-file (car files))))
        (should (string-match-p "0001" content))
        (should (string-match-p "Adopt Microservices" content))
        (should (string-match-p (format-time-string "%Y") content))
        (should-not (string-match-p "{{NUMBER}}" content))
        (should-not (string-match-p "{{TITLE}}" content))
        (should-not (string-match-p "{{DATE}}" content))))))

(ert-deftest blueprint-test-adr-new/sequential-numbering ()
  "Multiple ADRs are numbered sequentially."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "First decision")
      (blueprint-adr-new "Second decision")
      (blueprint-adr-new "Third decision")
      (let* ((adr-dir (expand-file-name ".blueprint/adr" proj))
             (files (sort (directory-files adr-dir nil "^[0-9]\\{4\\}-.*\\.org$")
                          #'string<)))
        (should (= 3 (length files)))
        (should (string-prefix-p "0001-" (nth 0 files)))
        (should (string-prefix-p "0002-" (nth 1 files)))
        (should (string-prefix-p "0003-" (nth 2 files)))))))

(ert-deftest blueprint-test-adr-new/has-status-keyword ()
  "New ADR contains #+STATUS: proposed."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-adr-new "Some Decision")
      (let* ((adr-dir (expand-file-name ".blueprint/adr" proj))
             (files (directory-files adr-dir t "^[0-9]\\{4\\}-.*\\.org$"))
             (content (blueprint-test--read-file (car files))))
        (should (string-match-p "proposed" content))))))

(provide 'blueprint-test-adr)
;;; blueprint-test-adr.el ends here
