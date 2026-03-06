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

;;; --- blueprint--sync-section (direct unit tests) ---

(ert-deftest blueprint-test-sync/sync-section-replaces-content ()
  "blueprint--sync-section replaces content between markers."
  (with-temp-buffer
    (insert "# @@start@@\nold content\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new content")
    (let ((result (buffer-string)))
      (should (string-match-p "new content" result))
      (should-not (string-match-p "old content" result)))))

(ert-deftest blueprint-test-sync/sync-section-preserves-markers ()
  "blueprint--sync-section keeps both markers intact."
  (with-temp-buffer
    (insert "# @@start@@\nold\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new")
    (let ((result (buffer-string)))
      (should (string-match-p "# @@start@@" result))
      (should (string-match-p "# @@end@@" result)))))

(ert-deftest blueprint-test-sync/sync-section-empty-content ()
  "blueprint--sync-section with empty content removes old content."
  (with-temp-buffer
    (insert "# @@start@@\nsome old content\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "")
    (let ((result (buffer-string)))
      (should-not (string-match-p "some old content" result))
      (should (string-match-p "# @@start@@" result))
      (should (string-match-p "# @@end@@" result)))))

(ert-deftest blueprint-test-sync/sync-section-missing-start-noop ()
  "blueprint--sync-section does nothing when start-marker is absent."
  (with-temp-buffer
    (insert "no markers here\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new")
    (should (string-match-p "no markers here" (buffer-string)))
    (should-not (string-match-p "new" (buffer-string)))))

(ert-deftest blueprint-test-sync/sync-section-missing-end-noop ()
  "blueprint--sync-section does nothing when end-marker is absent."
  (with-temp-buffer
    (insert "# @@start@@\nold content\nno end marker\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new")
    (should (string-match-p "old content" (buffer-string)))
    (should-not (string-match-p "new" (buffer-string)))))

(ert-deftest blueprint-test-sync/sync-section-end-must-follow-start ()
  "blueprint--sync-section does not match end-marker appearing before start.
This is the regression test for the bug where the end-marker was searched
from point-min, allowing a stray end-marker before the start-marker to be
matched, which caused delete-region to receive inverted arguments."
  (with-temp-buffer
    ;; Stray end-marker BEFORE start-marker — must be ignored.
    (insert "# @@end@@\nstray content\n# @@start@@\nreal content\n# @@end@@\n")
    ;; With the bug fix, the search for end-marker begins AFTER start-marker,
    ;; so the real end-marker is found and only "real content" is replaced.
    (blueprint--sync-section "# @@start@@" "# @@end@@" "replaced")
    (let ((result (buffer-string)))
      (should (string-match-p "replaced" result))
      (should-not (string-match-p "real content" result))
      ;; stray content before the start-marker must be untouched
      (should (string-match-p "stray content" result)))))

(ert-deftest blueprint-test-sync/sync-section-second-call-updates ()
  "Two sequential calls each update their own section independently."
  (with-temp-buffer
    (insert (concat "# @@start-a@@\nold-a\n# @@end-a@@\n"
                    "# @@start-b@@\nold-b\n# @@end-b@@\n"))
    (blueprint--sync-section "# @@start-a@@" "# @@end-a@@" "new-a")
    (blueprint--sync-section "# @@start-b@@" "# @@end-b@@" "new-b")
    (let ((result (buffer-string)))
      (should (string-match-p "new-a" result))
      (should (string-match-p "new-b" result))
      (should-not (string-match-p "old-a" result))
      (should-not (string-match-p "old-b" result)))))

(provide 'blueprint-test-sync)
;;; blueprint-test-sync.el ends here
