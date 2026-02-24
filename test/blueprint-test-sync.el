;;; blueprint-test-sync.el --- Tests for blueprint-sync.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for master.org synchronization with #+INCLUDE: directives.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-sync)

;;; --- blueprint--generate-includes ---

(ert-deftest blueprint-test-sync/generate-includes-empty ()
  "No components produce an empty include string."
  (blueprint-test--with-project
    (should (string= "" (blueprint--generate-includes)))))

(ert-deftest blueprint-test-sync/generate-includes-one ()
  "One component produces one #+INCLUDE: directive."
  (blueprint-test--with-project
    (blueprint-test--write-component "mycomp")
    (let ((includes (blueprint--generate-includes)))
      (should (string-match-p "INCLUDE" includes))
      (should (string-match-p "mycomp" includes)))))

(ert-deftest blueprint-test-sync/generate-includes-sorted ()
  "Include directives are sorted alphabetically by component name."
  (blueprint-test--with-project
    (blueprint-test--write-component "zebra")
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component "middle")
    (let ((includes (blueprint--generate-includes)))
      (let ((pos-alpha (string-match "alpha" includes))
            (pos-middle (string-match "middle" includes))
            (pos-zebra (string-match "zebra" includes)))
        (should (< pos-alpha pos-middle))
        (should (< pos-middle pos-zebra))))))

;;; --- blueprint-sync ---

(ert-deftest blueprint-test-sync/creates-master-when-absent ()
  "blueprint-sync creates master.org if it does not exist."
  (blueprint-test--with-project
    (blueprint-sync)
    (should (file-exists-p (expand-file-name "master.org" default-directory)))))

(ert-deftest blueprint-test-sync/inserts-includes-between-markers ()
  "After sync, master.org contains #+INCLUDE: between the sync markers."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-sync)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      (should (string-match-p blueprint-sync-start-marker content))
      (should (string-match-p blueprint-sync-end-marker content))
      (should (string-match-p "INCLUDE" content))
      (should (string-match-p "svc" content)))))

(ert-deftest blueprint-test-sync/updates-existing-markers ()
  "A second sync updates the include section without duplicating markers."
  (blueprint-test--with-project
    (blueprint-test--write-component "first")
    (blueprint-sync)
    (blueprint-test--write-component "second")
    (blueprint-sync)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      ;; Both components should appear exactly once
      (should (= 1 (cl-count-if (lambda (l) (string-match-p "first" l))
                                 (split-string content "\n"))))
      (should (= 1 (cl-count-if (lambda (l) (string-match-p "second" l))
                                 (split-string content "\n"))))
      ;; Markers appear exactly once each
      (should (= 1 (cl-count blueprint-sync-start-marker
                             (split-string content "\n") :test #'string=)))
      (should (= 1 (cl-count blueprint-sync-end-marker
                             (split-string content "\n") :test #'string=))))))

(ert-deftest blueprint-test-sync/preserves-manual-content ()
  "Content outside the sync markers is preserved across syncs."
  (blueprint-test--with-project
    (let ((master (expand-file-name "master.org" default-directory)))
      ;; Write a master with manual content and sync markers
      (with-temp-file master
        (insert "#+TITLE: My Project\n\n"
                "* Manual Section\n\nThis is written by hand.\n\n"
                blueprint-sync-start-marker "\n"
                blueprint-sync-end-marker "\n"))
      (blueprint-test--write-component "comp-a")
      (blueprint-sync)
      (let ((content (blueprint-test--read-file master)))
        (should (string-match-p "This is written by hand" content))
        (should (string-match-p "comp-a" content))))))

(ert-deftest blueprint-test-sync/minlevel-2 ()
  "Include directives use :minlevel 2."
  (blueprint-test--with-project
    (blueprint-test--write-component "lvl")
    (blueprint-sync)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      (should (string-match-p ":minlevel 2" content)))))

(provide 'blueprint-test-sync)
;;; blueprint-test-sync.el ends here
