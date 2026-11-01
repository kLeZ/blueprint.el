;;; blueprint-test-history.el --- Tests for blueprint-history.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the metrics history: recording (direct and through
;; `blueprint-sync'), deduplication, rows parsing and the SVG chart.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'blueprint-test-helpers)
(require 'blueprint-history)
(require 'blueprint-sync)

(defun blueprint-test-history--write-project ()
  "Create a fixture project whose document holds two components.
The master.org is written by hand (the template one carries marker
text of its own), so the recorded numbers are fully predictable:
alpha contributes one QUESTION (3 points), beta one FIXME (4)."
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
           "* Responsibility\n\n* Risks\n\n* Open Questions\n\n* Diagrams\n")))

(defun blueprint-test-history--history-content ()
  "Return the contents of the metrics history file."
  (blueprint-test--read-file (blueprint--history-file)))

(ert-deftest blueprint-test-history/record-creates-file-and-row ()
  "The first recording creates the file with header and one data row."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (let ((blueprint-history-on-sync nil))
      (blueprint-sync)
      (should (stringp (blueprint-history-record))))
    (let ((content (blueprint-test-history--history-content)))
      (should (string-match-p "^| Data | Score | Penalty | Words" content))
      (should (= 1 (with-temp-buffer
                     (insert content)
                     (goto-char (point-min))
                     (count-matches "^|[ \t]*[0-9]"))))
      ;; alpha QUESTION (3) + beta FIXME (4).
      (should (string-match-p "^| [0-9-]+ [0-9:]+ | [0-9]+ | 7 |" content)))))

(ert-deftest blueprint-test-history/record-skips-identical-values ()
  "A second recording with the same values does not add a row."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (let ((blueprint-history-on-sync nil))
      (blueprint-sync)
      (blueprint-history-record)
      (should (null (blueprint-history-record))))
    (should (= 1 (with-temp-buffer
                   (insert (blueprint-test-history--history-content))
                   (goto-char (point-min))
                   (count-matches "^|[ \t]*[0-9]"))))))

(ert-deftest blueprint-test-history/record-appends-changed-values ()
  "After the document changes, the next recording adds a row."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (let ((blueprint-history-on-sync nil))
      (blueprint-sync)
      (blueprint-history-record)
      (let ((arc (expand-file-name
                  ".blueprint/components/alpha/arc42.org" default-directory)))
        (append-to-file "\nMore text with QUESTION two.\n" nil arc)
        (blueprint--invalidate-cache)
        (should (stringp (blueprint-history-record))))
      (should (= 2 (with-temp-buffer
                     (insert (blueprint-test-history--history-content))
                     (goto-char (point-min))
                     (count-matches "^|[ \t]*[0-9]")))))))

(ert-deftest blueprint-test-history/rows-parse-numbers ()
  "`blueprint--history-rows' returns numeric rows, oldest first.
Row layout: (DATE SCORE PENALTY WORDS QUESTION TBD FIXME DA-VAL DA-REV)."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (let ((blueprint-history-on-sync nil))
      (blueprint-sync)
      (blueprint-history-record))
    (let ((rows (blueprint--history-rows (blueprint--history-file))))
      (should (= (length rows) 1))
      (let ((row (car rows)))
        (should (string-match-p "[0-9]\\{4\\}-[0-9]\\{2\\}" (car row)))
        (should (= (nth 2 row) 7))          ; penalty
        (should (= (nth 4 row) 1))          ; QUESTION
        (should (= (nth 6 row) 1))))))      ; FIXME

(ert-deftest blueprint-test-history/chart-svg-contains-points ()
  "The chart is a self-contained SVG with one point per row."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (blueprint-sync)
    (let ((blueprint-history-on-sync nil))
      (blueprint-history-record))
    (let* ((rows (blueprint--history-rows (blueprint--history-file)))
           (svg (blueprint--history-chart-svg rows)))
      (should (string-match-p "xmlns='http://www.w3.org/2000/svg'" svg))
      (should (string-match-p "<polyline points='[^']+'" svg))
      (should (= 1 (with-temp-buffer
                     (insert svg)
                     (goto-char (point-min))
                     (count-matches "[0-9]+\\.[0-9],[0-9]+\\.[0-9]")))))))

(ert-deftest blueprint-test-history/sync-records-by-default ()
  "With `blueprint-history-on-sync' at its default, sync records a row."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (blueprint-sync)
    (should (file-exists-p (blueprint--history-file)))
    (should (= 1 (with-temp-buffer
                   (insert (blueprint-test-history--history-content))
                   (goto-char (point-min))
                   (count-matches "^|[ \t]*[0-9]"))))))

(ert-deftest blueprint-test-history/sync-skips-when-disabled ()
  "With `blueprint-history-on-sync' nil, sync does not touch the history."
  (blueprint-test--with-project
    (blueprint-test-history--write-project)
    (let ((blueprint-history-on-sync nil))
      (blueprint-sync))
    (should-not (file-exists-p (blueprint--history-file)))))

(provide 'blueprint-test-history)
;;; blueprint-test-history.el ends here
