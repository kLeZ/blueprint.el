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

(ert-deftest blueprint-test-sync/generate-includes-headline-before-include ()
  "Each #+INCLUDE: is preceded by a level-2 headline naming the component."
  (blueprint-test--with-project
    (blueprint-test--write-component "mycomp")
    (let ((includes (blueprint--generate-includes)))
      (should (string-match-p "\\`\\*\\* .*\n#\\+INCLUDE" includes)))))

(ert-deftest blueprint-test-sync/generate-includes-uses-title-display-name ()
  "The headline uses the component's #+TITLE:, not the raw directory name."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "portale"
     (concat "#+TITLE: Portale -- Architettura (arc42)\n"
             "#+BLUEPRINT_DEPENDS:\n\n* Introduction\n\n"))
    (let ((includes (blueprint--generate-includes)))
      (should (string-match-p "\\*\\* Portale$" includes))
      (should-not (string-match-p "\\*\\* Portale --" includes)))))

(ert-deftest blueprint-test-sync/generate-includes-falls-back-to-capitalized-name ()
  "Without a parseable #+TITLE:, the headline falls back to NAME capitalized."
  (blueprint-test--with-project
    (blueprint-test--write-component "mycomp" "* Introduction\n\n")
    (let ((includes (blueprint--generate-includes)))
      (should (string-match-p "\\*\\* Mycomp$" includes)))))

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

;;; --- page breaks ---

(ert-deftest blueprint-test-sync/include-path-follows-directory-name ()
  "Include paths are relative to master.org and follow the data dir name."
  (let ((blueprint-directory-name "content/blueprint"))
    (blueprint-test--with-project
      (blueprint-test--write-component "svc")
      (should (string-match-p
               (regexp-quote
                "#+INCLUDE: \"content/blueprint/components/svc/arc42.org\" :minlevel 3")
               (blueprint--generate-includes-for "arc42.org"))))))

(ert-deftest blueprint-test-sync/page-breaks-between-components ()
  "With PAGE-BREAKS `components', a break precedes every headline but the first."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component "beta")
    (blueprint-test--write-component "gamma")
    (let* ((includes (blueprint--generate-includes-for "arc42.org" 'components))
           (lines (split-string includes "\n")))
      (should (= 2 (cl-count-if (lambda (l) (string-prefix-p "#+ODT:" l)) lines)))
      (should (= 2 (cl-count-if (lambda (l) (string-prefix-p "#+LATEX:" l)) lines)))
      ;; No break before the first component: the section opens with it.
      (should (string-prefix-p "** " (car lines)))
      ;; Each break sits right before a component headline.
      (should (string-match-p
               (concat (regexp-quote blueprint--page-break-lines) "\n\\*\\* ")
               includes)))))

(ert-deftest blueprint-test-sync/page-breaks-single-component-none ()
  "A single component gets no page break."
  (blueprint-test--with-project
    (blueprint-test--write-component "solo")
    (should-not (string-match-p
                 "#\\+ODT:"
                 (blueprint--generate-includes-for "arc42.org" 'components)))))

(ert-deftest blueprint-test-sync/page-breaks-off-by-default ()
  "Without PAGE-BREAKS no break is written."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component "beta")
    (should-not (string-match-p "#\\+ODT:"
                                (blueprint--generate-includes-for "arc42.org")))))

(ert-deftest blueprint-test-sync/page-break-mode-parsing ()
  "The keyword value is read case-insensitively; unknown values are ignored."
  (with-temp-buffer
    (insert "#+TITLE: X\n#+BLUEPRINT_PAGE_BREAK: Components \n")
    (should (eq 'components (blueprint--page-break-mode))))
  (with-temp-buffer
    (insert "#+TITLE: X\n#+BLUEPRINT_PAGE_BREAK: parts\n")
    (should-not (blueprint--page-break-mode)))
  (with-temp-buffer
    (insert "#+TITLE: X\n")
    (should-not (blueprint--page-break-mode))))

(ert-deftest blueprint-test-sync/sync-honours-page-break-keyword ()
  "blueprint-sync writes breaks only when master.org declares the keyword."
  (blueprint-test--with-project
    (let ((master (expand-file-name "master.org" default-directory)))
      (blueprint-test--write-component "alpha")
      (blueprint-test--write-component "beta")
      (with-temp-file master
        (insert "#+TITLE: P\n#+BLUEPRINT_PAGE_BREAK: components\n\n"
                blueprint-sync-start-marker "\n"
                blueprint-sync-end-marker "\n"))
      (blueprint-sync)
      (should (= 1 (cl-count-if
                    (lambda (l) (string-prefix-p "#+ODT:" l))
                    (split-string (blueprint-test--read-file master) "\n"))))
      ;; Removing the keyword and syncing again drops the breaks.
      (with-temp-file master
        (insert "#+TITLE: P\n\n"
                blueprint-sync-start-marker "\n"
                blueprint-sync-end-marker "\n"))
      (when (get-file-buffer master)
        (with-current-buffer (get-file-buffer master)
          (revert-buffer t t t)))
      (blueprint-sync)
      (should-not (string-match-p "#\\+ODT:" (blueprint-test--read-file master))))))

(ert-deftest blueprint-test-sync/insert-page-break ()
  "`blueprint-insert-page-break' writes the break at the start of the line."
  (with-temp-buffer
    (insert "prima\ndopo")
    (goto-char (point-max))
    (backward-char 2)
    (blueprint-insert-page-break)
    (should (string= (buffer-string)
                     (concat "prima\n" blueprint--page-break-lines "\ndopo")))))

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
      ;; Each component now appears on exactly two lines: its headline
      ;; and its #+INCLUDE:, not duplicated beyond that pair.
      (should (= 2 (cl-count-if (lambda (l) (string-match-p "first" l))
                                 (split-string content "\n"))))
      (should (= 2 (cl-count-if (lambda (l) (string-match-p "second" l))
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

(ert-deftest blueprint-test-sync/minlevel-3 ()
  "Include directives use :minlevel 3, nesting under the component headline."
  (blueprint-test--with-project
    (blueprint-test--write-component "lvl")
    (blueprint-sync)
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      (should (string-match-p ":minlevel 3" content)))))

;;; --- blueprint--sync-section (direct unit tests) ---

(ert-deftest blueprint-test-sync/sync-section-replaces-content ()
  "blueprint--sync-section replaces content between markers."
  (with-temp-buffer
    (insert "# @@start@@\nold content\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new content")
    (let ((result (buffer-string)))
      (should (string-match-p "new content" result))
      (should-not (string-match-p "old content" result)))))

(ert-deftest blueprint-test-sync/sync-section-no-spurious-blank-line ()
  "blueprint--sync-section does not insert a blank line between
start-marker and CONTENT on every sync (regression test for the
extra-blank-line cosmetic bug)."
  (with-temp-buffer
    (insert "# @@start@@\nold content\n# @@end@@\n")
    (blueprint--sync-section "# @@start@@" "# @@end@@" "new content")
    (let ((result (buffer-string)))
      (should (string-match-p "# @@start@@\nnew content\n# @@end@@" result)))))

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
