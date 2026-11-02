;;; blueprint-test-dashboard.el --- Tests for blueprint-dashboard.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for dashboard entry building, status classification, and
;; focus-mode filtering; marker aggregation over all the documents of
;; a component in the dashboard, the dependency graph colors and the
;; daily workflow candidates.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-dashboard)
(require 'blueprint-graph)
(require 'blueprint-daily)
(require 'blueprint-risks)

(ert-deftest blueprint-test-dashboard/status-ok-with-no-markers ()
  (should (equal (blueprint--component-status 0 0 0) "OK")))

(ert-deftest blueprint-test-dashboard/status-in-progress-with-few-markers ()
  (should (equal (blueprint--component-status 1 1 0) "IN-PROGRESS")))

(ert-deftest blueprint-test-dashboard/status-needs-work-with-many-questions ()
  (should (equal (blueprint--component-status 3 0 0) "NEEDS-WORK")))

(ert-deftest blueprint-test-dashboard/status-fixme-takes-priority ()
  "A single FIXME outranks question/TBD counts, however low."
  (should (equal (blueprint--component-status 0 0 1) "FIXME")))

(ert-deftest blueprint-test-dashboard/entries-include-all-components ()
  "blueprint--dashboard-entries lists every component when focus is off."
  (blueprint-test--with-project
    (let ((blueprint-dashboard-focus nil))
      (blueprint-test--write-component "alpha")
      (blueprint-test--write-component "beta")
      (let ((ids (mapcar #'car (blueprint--dashboard-entries))))
        (should (member "alpha" ids))
        (should (member "beta" ids))))))

(ert-deftest blueprint-test-dashboard/entries-sorted-by-name ()
  "blueprint--dashboard-entries is sorted alphabetically by component id."
  (blueprint-test--with-project
    (let ((blueprint-dashboard-focus nil))
      (blueprint-test--write-component "zeta")
      (blueprint-test--write-component "alpha")
      (should (equal (mapcar #'car (blueprint--dashboard-entries))
                     '("alpha" "zeta"))))))

(ert-deftest blueprint-test-dashboard/focus-mode-filters-clean-components ()
  "With focus mode on, only components with open markers are listed."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean")
    (blueprint-test--write-component
     "noisy"
     (concat "#+TITLE: noisy\n#+BLUEPRINT_DEPENDS:\n\n"
             "* Open Questions\n\n- QUESTION something unresolved\n"))
    (let* ((blueprint-dashboard-focus t)
           (ids (mapcar #'car (blueprint--dashboard-entries))))
      (should (member "noisy" ids))
      (should-not (member "clean" ids)))))

(ert-deftest blueprint-test-dashboard/entries-carry-owner-and-tech-columns ()
  "Owner/Tech keywords from the component file surface as dashboard columns."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc"
     (concat "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n"
             "#+BLUEPRINT_OWNER: Team Payments\n"
             "#+BLUEPRINT_TECH: Java\n\n* Introduction\n\n"))
    (let* ((blueprint-dashboard-focus nil)
           (entry (assoc "svc" (blueprint--dashboard-entries)))
           (fields (cadr entry)))
      (should (equal (aref fields 1) "Team Payments"))
      (should (equal (aref fields 2) "Java")))))

(ert-deftest blueprint-test-dashboard/entries-carry-scope-column ()
  "The Scope column reflects each component's #+BLUEPRINT_STATUS:."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "legacy"
     "#+TITLE: legacy\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\n")
    (let* ((blueprint-dashboard-focus nil)
           (blueprint-dashboard-out-of-scope-only nil)
           (entry (assoc "legacy" (blueprint--dashboard-entries)))
           (fields (cadr entry)))
      (should (equal (aref fields 3) "out-of-scope")))))

(ert-deftest blueprint-test-dashboard/entries-carry-lifecycle-column ()
  "The Life column reflects #+BLUEPRINT_LIFECYCLE: (default active),
with a face on the non-active values, and no column was displaced."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "old" "#+TITLE: old\n#+BLUEPRINT_LIFECYCLE: deprecated\n\n* Introduction\n\n")
    (blueprint-test--write-component "new")
    (let* ((blueprint-dashboard-focus nil)
           (old (cadr (assoc "old" (blueprint--dashboard-entries))))
           (new (cadr (assoc "new" (blueprint--dashboard-entries)))))
      (should (= (length blueprint--dashboard-columns) 14))
      (should (equal (substring-no-properties (aref old 4)) "deprecated"))
      (should (equal (get-text-property 0 'face (aref old 4)) 'error))
      (should (equal (aref new 4) "active"))
      ;; The numeric columns keep their indices.
      (should (equal (aref old 5) "0"))  ; QUESTION
      (should (equal (aref old 10) "0")) ; Penalty
      (should (equal (substring-no-properties (aref old 13)) "OK")))))

(ert-deftest blueprint-test-dashboard/out-of-scope-filter-hides-in-scope ()
  "With the out-of-scope filter on, in-scope components are hidden."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean")
    (blueprint-test--write-component
     "legacy"
     "#+TITLE: legacy\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\n")
    (let* ((blueprint-dashboard-focus nil)
           (blueprint-dashboard-out-of-scope-only t)
           (ids (mapcar #'car (blueprint--dashboard-entries))))
      (should (member "legacy" ids))
      (should-not (member "clean" ids)))))

(ert-deftest blueprint-test-dashboard/out-of-scope-filter-off-shows-all ()
  "With the out-of-scope filter off, every component is listed."
  (blueprint-test--with-project
    (blueprint-test--write-component "clean")
    (blueprint-test--write-component
     "legacy"
     "#+TITLE: legacy\n#+BLUEPRINT_STATUS: out-of-scope\n\n* Introduction\n\n")
    (let* ((blueprint-dashboard-focus nil)
           (blueprint-dashboard-out-of-scope-only nil)
           (ids (mapcar #'car (blueprint--dashboard-entries))))
      (should (member "legacy" ids))
      (should (member "clean" ids)))))

(ert-deftest blueprint-test-dashboard/line-count-of-missing-file-is-zero ()
  (should (= 0 (blueprint--component-line-count nil)))
  (should (= 0 (blueprint--component-line-count "/nonexistent/path.org"))))

;;; --- All the documents of a component ---

(defun blueprint-test--dashboard-fields (id)
  "Return the dashboard column vector of component ID."
  (let ((blueprint-dashboard-focus nil)
        (blueprint-dashboard-out-of-scope-only nil))
    (cadr (assoc id (blueprint--dashboard-entries)))))

(ert-deftest blueprint-test-dashboard/status-counts-methodology-markers ()
  "Open methodology markers keep a component out of \"OK\"."
  (should (equal (blueprint--component-status 0 0 0 0) "OK"))
  (should (equal (blueprint--component-status 0 0 0 2) "IN-PROGRESS")))

(ert-deftest blueprint-test-dashboard/entries-sum-all-documents ()
  "Marker columns sum arc42.org, functional.org and infrastructure.org.
Penalty and Health follow `blueprint--health-weights' ([FINDING] 0)."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" "#+TITLE: svc\n\n* Open Questions\n\n- QUESTION one\n")
    (blueprint-test--write-document
     "svc" "functional.org"
     "#+TITLE: f\n\n* Area\n\nTBD rule. [DA VALIDARE] [FINDING] text.\n")
    (blueprint-test--write-document
     "svc" "infrastructure.org"
     "#+TITLE: i\n\n* Servers\n\nFIXME host. [DA REVISIONARE] [FINDING]\n")
    (let ((fields (blueprint-test--dashboard-fields "svc"))
          (summary (blueprint--component-health-summary "svc")))
      (should (equal (aref fields 5) "1"))  ; QUESTION (arc42)
      (should (equal (aref fields 6) "1"))  ; TBD (functional)
      (should (equal (aref fields 7) "1"))  ; FIXME (infrastructure)
      (should (equal (aref fields 8) "1"))  ; [DA VALIDARE]
      (should (equal (aref fields 9) "1"))  ; [DA REVISIONARE]
      (should (equal (aref fields 10) "2")) ; [FINDING], both files
      ;; 3 + 2 + 4 + 1 + 1, findings weigh 0.
      (should (equal (aref fields 11) "11"))
      (should (= 11 (plist-get summary :penalty)))
      (should (= 5 (plist-get summary :open)))
      (should (equal (aref fields 12)
                     (number-to-string
                      (blueprint--health-score-from
                       11 (plist-get summary :words)))))
      (should (equal (aref fields 13) "FIXME"))
      ;; The project score is the same computation over all components.
      (should (= (blueprint-health-score)
                 (string-to-number (aref fields 12)))))))

(ert-deftest blueprint-test-dashboard/focus-sees-functional-markers ()
  "Focus mode lists a component whose only open marker is in functional.org."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-document
     "svc" "functional.org" "#+TITLE: f\n\n* Area\n\n[DA VALIDARE] rule.\n")
    (blueprint-test--write-component "clean")
    (let* ((blueprint-dashboard-focus t)
           (blueprint-dashboard-out-of-scope-only nil)
           (ids (mapcar #'car (blueprint--dashboard-entries))))
      (should (member "svc" ids))
      (should-not (member "clean" ids)))))

(ert-deftest blueprint-test-dashboard/focus-ignores-findings ()
  "A component whose only markers are [FINDING] has no open points."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-document
     "svc" "infrastructure.org" "#+TITLE: i\n\n* Servers\n\n[FINDING] old OS.\n")
    (let* ((blueprint-dashboard-focus t)
           (blueprint-dashboard-out-of-scope-only nil))
      (should-not (assoc "svc" (blueprint--dashboard-entries))))
    (should (equal (aref (blueprint-test--dashboard-fields "svc") 13) "OK"))
    (should (null (blueprint--daily-candidates)))))

(ert-deftest blueprint-test-dashboard/visit-asks-document ()
  "RET in the dashboard opens the document chosen among the three."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (let ((infra (blueprint-test--write-document
                  "svc" "infrastructure.org" "i\n")))
      (cl-letf (((symbol-function 'tabulated-list-get-id) (lambda () "svc"))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "infrastructure.org")))
        (with-current-buffer (blueprint-dashboard-visit)
          (should (equal (buffer-file-name) infra)))))))

(ert-deftest blueprint-test-dashboard/cache-shared-with-risks ()
  "The dashboard's cached stats do not clobber what risks reads.
`blueprint--detect-risks' sums the cached technical metrics of
arc42.org; a different shape under the same key would break it."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "svc" "#+TITLE: svc\n\n* Open Questions\n\n- QUESTION one\n")))
      (blueprint--invalidate-cache)
      (blueprint--dashboard-entries)
      (should (listp (blueprint--detect-risks file)))
      (should (equal (blueprint--cached-metrics
                      file #'blueprint--component-metrics)
                     '(1 0 0)))
      (blueprint--dashboard-entries)
      (should (equal (aref (blueprint-test--dashboard-fields "svc") 5) "1")))))

(ert-deftest blueprint-test-graph/color-uses-all-documents ()
  "The graph color follows the score over all documents of a component."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" "#+TITLE: svc\n\n* Introduction\n\nShort text.\n")
    (should (equal (blueprint--graph-health-color "svc") "#6bcb77"))
    ;; Many open points in infrastructure.org, almost no words.
    (blueprint-test--write-document
     "svc" "infrastructure.org" "#+TITLE: i\n\n* Servers\n\nFIXME FIXME\n")
    (should (equal (blueprint--graph-health-color "svc") "#ff6b6b"))))

(ert-deftest blueprint-test-graph/findings-keep-green ()
  "[FINDING] markers alone leave a component green."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-document
     "svc" "functional.org" "#+TITLE: f\n\n* Area\n\n[FINDING] [FINDING]\n")
    (should (equal (blueprint--graph-health-color "svc") "#6bcb77"))))

(ert-deftest blueprint-test-graph/score-color-thresholds ()
  (should (equal (blueprint--health-score-color 49) "#ff6b6b"))
  (should (equal (blueprint--health-score-color 50) "#ffd93d"))
  (should (equal (blueprint--health-score-color 79) "#ffd93d"))
  (should (equal (blueprint--health-score-color 80) "#6bcb77")))

(ert-deftest blueprint-test-graph/score-color-follows-delivery-threshold ()
  "The yellow/green threshold is `blueprint-delivery-score-threshold':
customizing it moves the green edge of the graphs."
  (let ((blueprint-delivery-score-threshold 60))
    (should (equal (blueprint--health-score-color 59) "#ffd93d"))
    (should (equal (blueprint--health-score-color 60) "#6bcb77")))
  (let ((blueprint-delivery-score-threshold 90))
    (should (equal (blueprint--health-score-color 85) "#ffd93d"))
    (should (equal (blueprint--health-score-color 90) "#6bcb77")))
  ;; The red edge stays at the CI threshold.
  (let ((blueprint-delivery-score-threshold 30))
    (should (equal (blueprint--health-score-color 49) "#ff6b6b"))
    (should (equal (blueprint--health-score-color 50) "#6bcb77"))))

(ert-deftest blueprint-test-daily/candidates-weighted-over-documents ()
  "Daily candidates sum all documents and sort by penalty points."
  (blueprint-test--with-project
    (blueprint-test--write-component "light")
    (blueprint-test--write-document
     "light" "functional.org" "#+TITLE: f\n\n* A\n\n[DA VALIDARE]\n")
    (blueprint-test--write-component "heavy")
    (blueprint-test--write-document
     "heavy" "infrastructure.org" "#+TITLE: i\n\n* S\n\nFIXME\n")
    (blueprint-test--write-component "clean")
    (let ((cands (blueprint--daily-candidates)))
      (should (equal (mapcar #'car cands) '("heavy" "light")))
      (should (= 4 (plist-get (cdr (assoc "heavy" cands)) :penalty)))
      (should (= 1 (plist-get (cdr (assoc "light" cands)) :penalty))))))

(ert-deftest blueprint-test-daily/opens-document-with-most-penalty ()
  "`blueprint-daily' preselects the document with most penalty points."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "svc" "#+TITLE: svc\n\n* Introduction\n\n[DA VALIDARE]\n")
    (let ((func (blueprint-test--write-document
                 "svc" "functional.org" "#+TITLE: f\n\n* A\n\nQUESTION x\n"))
          (blueprint-dashboard-focus nil)
          (prompts '()))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt collection &rest args)
                   (push prompt prompts)
                   (if (string-prefix-p "Work on" prompt)
                       (car collection)
                     ;; Accept the default document.
                     (nth 4 args)))))
        (save-window-excursion
          (blueprint-daily)
          (should (equal (buffer-file-name) func))))
      (should (= 2 (length prompts)))
      (when (get-buffer "*Blueprint*") (kill-buffer "*Blueprint*")))))

;;; --- Column titles and rows of the whole document (PLAN 9.31) ---

(ert-deftest blueprint-test-dashboard/column-titles-visible ()
  "The column titles stay in the header line after refresh and toggles.
Regression: the refresh replaced the header line holding the titles
with the summary, so the numbers had no titles; the summary now goes
to the mode line."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (let ((blueprint-dashboard-focus nil)
          (blueprint-dashboard-out-of-scope-only nil))
      (unwind-protect
          (save-window-excursion
            (blueprint-dashboard)
            (dolist (step (list #'ignore
                                #'blueprint-dashboard-refresh
                                #'blueprint-dashboard-toggle-focus
                                #'blueprint-dashboard-toggle-focus))
              (with-current-buffer "*Blueprint*"
                (cl-letf (((symbol-function 'message) #'ignore))
                  (funcall step)))
              (with-current-buffer "*Blueprint*"
                (should tabulated-list-use-header-line)
                (should header-line-format)
                (let ((header (mapconcat
                               (lambda (part)
                                 (if (stringp part)
                                     (substring-no-properties part)
                                   ""))
                               (if (listp header-line-format)
                                   header-line-format
                                 (list header-line-format))
                               "")))
                  (dolist (title '("Name" "QUESTION" "TBD" "FIXME" "DA VAL" "DA REV"
                                   "FINDING" "Penalty" "Health" "Status"))
                    (should (string-match-p (regexp-quote title) header))))
                (should (stringp mode-line-process))
                (should (string-match-p "Health: [0-9]+" mode-line-process)))))
        (kill-buffer "*Blueprint*")))))

(ert-deftest blueprint-test-dashboard/column-titles-fit-widths ()
  "No column title is wider than its column."
  (dolist (col blueprint--dashboard-columns)
    (should (<= (length (car col)) (cadr col)))))

(ert-deftest blueprint-test-dashboard/rows-for-other-files ()
  "Files of the document outside the components get rows of their own.
Components first, then the other files in document order; a component
with nothing in master.org is NOT-INCLUDED."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc" "#+TITLE: svc\n\n* I\n\nText.\n")
    (blueprint-test--write-component "off")
    (blueprint-test--write-master "glossary.org" ".blueprint/components/svc/arc42.org"
                                  "nfr/risks.org")
    (blueprint-test--write-file "glossary.org" "* G\n\nTermine [DA VALIDARE].\n")
    (blueprint-test--write-file "nfr/risks.org" "* R\n\nQUESTION aperta.\n")
    (let* ((blueprint-dashboard-focus nil)
           (blueprint-dashboard-out-of-scope-only nil)
           (entries (blueprint--dashboard-entries)))
      (should (equal (mapcar #'car entries)
                     '("off" "svc" "master.org" "glossary.org" "nfr/risks.org")))
      (let ((g (cadr (assoc "glossary.org" entries)))
            (r (cadr (assoc "nfr/risks.org" entries)))
            (off (cadr (assoc "off" entries))))
        (should (equal (aref g 8) "1"))
        (should (equal (aref g 11) "1"))
        (should (equal (aref r 5) "1"))
        (should (equal (aref r 13) "IN-PROGRESS"))
        (should (equal (aref off 13) "NOT-INCLUDED"))
        (should (equal (aref off 12) "-")))
      ;; Focus: rows with penalty points, and the component left out.
      (let ((blueprint-dashboard-focus t))
        (should (equal (mapcar #'car (blueprint--dashboard-entries))
                       '("off" "glossary.org" "nfr/risks.org")))))))

(ert-deftest blueprint-test-dashboard/visit-part-row ()
  "RET on the row of a file outside the components visits that file."
  (blueprint-test--with-project
    (blueprint-test--write-master "nfr/risks.org")
    (let ((risks (blueprint-test--write-file "nfr/risks.org" "* R\n")))
      (cl-letf (((symbol-function 'tabulated-list-get-id)
                 (lambda () "nfr/risks.org")))
        (with-current-buffer (blueprint-dashboard-visit)
          (should (equal (buffer-file-name) risks)))))))

(ert-deftest blueprint-test-daily/candidates-include-parts ()
  "The daily workflow proposes files outside the components too."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-master ".blueprint/components/svc/arc42.org" "nfr/risks.org")
    (blueprint-test--write-file "nfr/risks.org" "* R\n\nFIXME\n")
    (should (equal (mapcar #'car (blueprint--daily-candidates))
                   '("nfr/risks.org")))))

(ert-deftest blueprint-test-graph/not-included-is-grey ()
  "A component with no document in master.org is grey in the graphs."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-component "off")
    (blueprint-test--write-master ".blueprint/components/svc/arc42.org")
    (should (equal (blueprint--graph-health-color "svc") "#6bcb77"))
    (should (equal (blueprint--graph-health-color "off") blueprint--not-included-color))))

;;; --- Milestones (9.11) ---

(ert-deftest blueprint-test-dashboard/milestone-summary-from-todo-file ()
  "Next milestone = first TODO heading in file order; the open count
is the number of TODO headings across all the milestone files; a
:DEADLINE: on the next milestone becomes its date."
  (blueprint-test--with-project
    (blueprint-test--write-file
     "TODO.org"
     (concat "* TODO Consegna parziale\nDEADLINE: <2026-12-01 lun>\n\n"
             "* DONE Fatto\n\n* TODO Rilascio finale\n"))
    (let ((m (blueprint--milestone-summary)))
      (should (string= (plist-get m :title) "Consegna parziale"))
      (should (string= (plist-get m :date) "2026-12-01"))
      (should (= (plist-get m :open) 2))
      (should (string= (plist-get m :file) "TODO.org")))))

(ert-deftest blueprint-test-dashboard/milestone-summary-no-files ()
  "No milestone file at the root: no summary."
  (blueprint-test--with-project
    (should (null (blueprint--milestone-summary)))))

(ert-deftest blueprint-test-dashboard/milestone-in-summary-line ()
  "The dashboard summary line carries the milestone when a file exists,
and says nothing when there is none."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (should-not (string-match-p "Milestone:"
                                (blueprint--dashboard-summary-line)))
    (blueprint-test--write-file "CRONOPROGRAMMA.org" "* TODO Consegna draft\n")
    (let ((line (blueprint--dashboard-summary-line)))
      (should (string-match-p "Milestone: Consegna draft" line))
      (should (string-match-p "TODO aperti: 1" line)))))

(ert-deftest blueprint-test-dashboard/milestone-malformed-file-does-not-break ()
  "Whatever happens while parsing the milestone files, the summary
degrades to nil instead of breaking the dashboard."
  (blueprint-test--with-project
    (blueprint-test--write-file "TODO.org" "* TODO Qualcosa\n")
    (cl-letf (((symbol-function 'org-element-parse-buffer)
               (lambda (&rest _) (error "boom"))))
      (should (null (blueprint--milestone-summary))))))

(ert-deftest blueprint-test-graph/dot-ids-are-quoted ()
  "Component ids are slugs with hyphens: unquoted they are a DOT syntax
error.  Both the dashboard SVG and the Graphviz dependency graph quote
them and render."
  (skip-unless (executable-find "dot"))
  (blueprint-test--with-project
    (blueprint-test--write-component
     "order-service"
     "#+TITLE: order-service\n#+BLUEPRINT_DEPENDS: auth-db\n\n* Introduction\n")
    (blueprint-test--write-component "auth-db" "#+TITLE: auth-db\n")
    (let ((svg (blueprint--dashboard-svg-generate)))
      (should (file-exists-p svg))
      (should (string-match-p "order&#45;service" (blueprint-test--read-file svg))))
    (let ((svg (blueprint--graph-graphviz (blueprint--graph-deps)
                                          (blueprint--root))))
      (should (string-suffix-p ".svg" svg))
      (should (string-match-p "auth&#45;db" (blueprint-test--read-file svg))))))

(ert-deftest blueprint-test-graph/dot-failure-signals ()
  "A failing `dot' is an error, not the path of an SVG never written."
  (skip-unless (executable-find "dot"))
  (let ((dot (make-temp-file "bp-" nil ".dot" "digraph { a -> ; }"))
        (svg (make-temp-file "bp-" nil ".svg")))
    (delete-file svg)
    (unwind-protect
        (should-error (blueprint--dot-render dot svg))
      (ignore-errors (delete-file dot)))))

(provide 'blueprint-test-dashboard)
;;; blueprint-test-dashboard.el ends here
