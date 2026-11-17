;;; blueprint-dashboard.el --- Magit-style dashboard for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Provides a `tabulated-list-mode' dashboard of the document: one row
;; per component, with its markers summed over every document of the
;; component that master.org includes (arc42.org, functional.org,
;; infrastructure.org), then one row per other file of the document
;; (master.org itself, glossary, Parte I and Parte V files,
;; references...).  Each row shows counts per marker, penalty points
;; and score with the weights of the health score (see
;; `blueprint--files-health-summary'), so the rows add up to
;; `blueprint-health-score'.  Supports focus mode to filter to rows
;; with open points, and an SVG overview of the components via
;; Graphviz.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)
(require 'blueprint-upgrade)

(defvar blueprint-dashboard-focus nil
  "When non-nil, dashboard shows only components with open markers.")

(defvar blueprint-dashboard-out-of-scope-only nil
  "When non-nil, dashboard shows only out-of-scope/tbd components.
Toggled by `blueprint-dashboard-toggle-out-of-scope', for reviewing
which components were excluded from the assessment perimeter and why.")

(defun blueprint--component-line-count (file)
  "Return the number of lines in FILE."
  (if (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (count-lines (point-min) (point-max)))
    0))

(defun blueprint--component-status (questions tbds fixmes &optional methodology)
  "Return a status string based on QUESTIONS, TBDS, and FIXMES counts.
METHODOLOGY is the number of open methodology markers ([TO VALIDATE],
[TO REVIEW]); [FINDING] is not one.  A component with any open
marker is never \"OK\"."
  (cond
   ((> fixmes 0) "FIXME")
   ((> questions 2) "NEEDS-WORK")
   ((> (+ questions tbds (or methodology 0)) 0) "IN-PROGRESS")
   (t "OK")))

(defconst blueprint--dashboard-not-included "NOT-INCLUDED"
  "Status of a component none of whose documents is in master.org.
Its counts are zero because nothing of it reaches the document.")

(defun blueprint--dashboard-lifecycle-label (lifecycle)
  "Return the display label of the LIFECYCLE status, with its face.
\"active\" is plain; \"draft\" is dimmed, \"deprecated\" red and
\"archived\" yellow, so the life cycle is legible at a glance."
  (pcase lifecycle
    ("draft" (propertize "draft" 'face 'shadow))
    ("deprecated" (propertize "deprecated" 'face 'error))
    ("archived" (propertize "archived" 'face 'warning))
    (_ "active")))

(defun blueprint--dashboard-row (unit)
  "Return the (ID VECTOR) dashboard entry of UNIT, or nil if filtered out.
UNIT is a row of `blueprint--document-units'.  Focus mode keeps rows
with penalty points and components not included in master.org; the
out-of-scope filter keeps out-of-scope/tbd components only."
  (let* ((id (plist-get unit :id))
         (component (eq (plist-get unit :kind) 'component))
         (file (and component (blueprint--component-file id)))
         (summary (blueprint--unit-health-summary unit))
         (counts (plist-get summary :counts))
         (count (lambda (re) (blueprint--health-marker-count counts re)))
         (questions (funcall count "\\<QUESTION\\>"))
         (tbds (funcall count "\\<TBD\\>"))
         (fixmes (funcall count "\\<FIXME\\>"))
         (to-validate (funcall count blueprint--to-validate-regexp))
         (to-review (funcall count blueprint--to-review-regexp))
         (findings (funcall count "\\[FINDING\\]"))
         (penalty (plist-get summary :penalty))
         (included (plist-get unit :included))
         (scope (if component (blueprint--component-scope-status id) ""))
         (lifecycle (if component
                        (blueprint--component-lifecycle-status id)
                      ""))
         (status (if included
                     (blueprint--component-status
                      questions tbds fixmes (+ to-validate to-review))
                   blueprint--dashboard-not-included)))
    (when (and (or (not blueprint-dashboard-focus)
                   (> penalty 0)
                   (not included))
               (or (not blueprint-dashboard-out-of-scope-only)
                   (and component (not (string= scope "in-scope")))))
      (list id (vector id
                       (or (and file (blueprint--org-keyword file "BLUEPRINT_OWNER")) "")
                       (or (and file (blueprint--org-keyword file "BLUEPRINT_TECH")) "")
                       scope
                       (blueprint--dashboard-lifecycle-label lifecycle)
                       (number-to-string questions)
                       (number-to-string tbds)
                       (number-to-string fixmes)
                       (number-to-string to-validate)
                       (number-to-string to-review)
                       (number-to-string findings)
                       (number-to-string penalty)
                       (if included (number-to-string (plist-get summary :score)) "-")
                       status)))))

(defun blueprint--dashboard-entries ()
  "Build tabulated-list entries for the dashboard.
One row per row of `blueprint--document-units': components first, in
alphabetical order, then the other files of the document in document
order, identified by their path relative to the project root.  Marker
columns count QUESTION, TBD, FIXME, [TO VALIDATE], [TO REVIEW]
and [FINDING] in the row's files, then come the weighted penalty
points and the row's own score, computed as `blueprint-health-score'
does for the whole document ([FINDING] weighs 0).  Every file of the
document is in exactly one row, so the penalty points of the rows add
up to those of the document.  A component with no document in
master.org shows the status `blueprint--dashboard-not-included'."
  (delq nil (mapcar #'blueprint--dashboard-row (blueprint--document-units))))

(defun blueprint--dashboard-numeric-sorter (column)
  "Return a `tabulated-list' sort predicate comparing COLUMN as numbers."
  (lambda (a b)
    (< (string-to-number (aref (cadr a) column))
       (string-to-number (aref (cadr b) column)))))

(defvar blueprint-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'blueprint-dashboard-visit)
    (define-key map (kbd "g") #'blueprint-dashboard-refresh)
    (define-key map (kbd "F") #'blueprint-dashboard-toggle-focus)
    (define-key map (kbd "O") #'blueprint-dashboard-toggle-out-of-scope)
    (define-key map (kbd "G") #'blueprint-dashboard-svg)
    (define-key map (kbd "u") #'blueprint-project-upgrade)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `blueprint-dashboard-mode'.")

(defconst blueprint--dashboard-columns
  '(("Name" 27) ("Owner" 8) ("Tech" 10) ("Scope" 12) ("Life" 11)
    ("QUESTION" 8) ("TBD" 4) ("FIXME" 5) ("TO VAL" 6) ("TO REV" 6)
    ("FINDING" 7) ("Penalty" 7) ("Health" 6) ("Status" 12))
  "Titles and widths of the dashboard columns, in order.
Every width is at least as large as its title, so no title is cut.")

(define-derived-mode blueprint-dashboard-mode tabulated-list-mode "Blueprint"
  "Major mode for the Blueprint project dashboard.
One row per component, then one per other file of the document
\(master.org, glossary, enterprise and NFR files, references).  Columns:

  Name      component id, or path of the file relative to the root
  Owner, Tech, Scope, Life
            #+BLUEPRINT_OWNER, #+BLUEPRINT_TECH, #+BLUEPRINT_STATUS
            and #+BLUEPRINT_LIFECYCLE of a component's arc42.org
  QUESTION, TBD, FIXME
            technical markers
  TO VAL    [TO VALIDATE] markers (and the Italian [DA VALIDARE])
  TO REV    [TO REVIEW] markers (and the Italian [DA REVISIONARE])
  FINDING   [FINDING] markers (weight 0, information only)
  Penalty   weighted penalty points, as in `blueprint-health-score'
  Health    score of the row alone (\"-\" when not in the document)
  Status    OK, IN-PROGRESS, NEEDS-WORK, FIXME, or NOT-INCLUDED for
            a component with no document in master.org

Only the text that master.org includes counts (see
`blueprint--document-files').  The column titles are in the header
line; the mode line shows the health score of the whole document,
the number of rows of each kind and the active filters.

\\{blueprint-dashboard-mode-map}"
  (setq tabulated-list-format
        (apply #'vector
               (cl-loop for (title width) in blueprint--dashboard-columns
                        for i from 0
                        collect (list title width
                                      (if (<= 4 i 11)
                                          (blueprint--dashboard-numeric-sorter i)
                                        t)
                                      :right-align (<= 4 i 11)))))
  ;; Column titles in the header line, where `tabulated-list' aligns
  ;; them with the rows also when line numbers are displayed; titles
  ;; printed in the buffer (`tabulated-list-use-header-line' nil) are
  ;; shifted by the width of the line-number column.  The summary goes
  ;; to the mode line (`blueprint-dashboard-refresh').
  (when (fboundp 'header-line-indent-mode)
    (header-line-indent-mode 1))
  (tabulated-list-init-header))

(defun blueprint-dashboard-visit ()
  "Open a document of the row at point.
For a component with more than one document (arc42.org,
functional.org, infrastructure.org) ask which, as
`blueprint-visit-component' does; for any other file of the document
visit it."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id
      (blueprint-visit-component id))))

(defcustom blueprint-milestone-files '("CRONOPROGRAMMA.org" "TODO.org")
  "Org files at the project root that hold the project's milestones.
When one of them exists, the dashboard summary shows the next open
milestone and the number of open TODO items (see
`blueprint--milestone-summary').  Milestones are headings with the
TODO keyword; the next one is the first in file order.  Set to nil to
disable the whole feature."
  :type '(repeat string)
  :group 'blueprint)

(defun blueprint--milestone-summary (&optional root)
  "Return the milestone summary of the project at ROOT, or nil.
Scans `blueprint-milestone-files' at the project root with
org-element: the next milestone is the first heading with the TODO
keyword in file order (a :DEADLINE: on it is reported as its date)
and the open count is the number of TODO headings across all the
files.  Returns nil when none of the files exists, none has a TODO
heading, or the feature is disabled.  Every parsing problem is
swallowed: a malformed milestone file must never break the dashboard."
  (when blueprint-milestone-files
    (condition-case nil
        (let* ((root (or root (blueprint--root)))
               (files (cl-remove-if-not
                       (lambda (f)
                         (file-exists-p (expand-file-name f root)))
                       blueprint-milestone-files))
               (todos '()))
          (dolist (f files)
            (with-temp-buffer
              (blueprint--insert-org-file (expand-file-name f root))
              (org-element-map (org-element-parse-buffer 'headline)
                  'headline
                (lambda (hl)
                  (when (equal (org-element-property :todo-keyword hl) "TODO")
                    (let ((d (org-element-property :deadline hl)))
                      (push (list :title
                                  (or (org-element-property :raw-value hl) "")
                                  :date (and d (format "%04d-%02d-%02d"
                                                       (org-element-property :year-start d)
                                                       (org-element-property :month-start d)
                                                       (org-element-property :day-start d)))
                                  :file f)
                            todos)))))))
          (when todos
            (let ((todos (nreverse todos)))
              (append (car todos) (list :open (length todos))))))
      (error nil))))

(defcustom blueprint-dashboard-show-version t
  "When non-nil, the dashboard summary shows the project version.
The Blueprint version of the project (declared in blueprint-version.org
or inferred from its layout), the number of optional migrations
available and of project/user templates older than the system ones or
customized; `u' in the dashboard opens the plan
\(`blueprint-project-upgrade')."
  :type 'boolean
  :group 'blueprint)

(defun blueprint--dashboard-version-part ()
  "Return the version part of the dashboard summary, or nil.
See `blueprint-dashboard-show-version'."
  (when blueprint-dashboard-show-version
    (let ((u (blueprint--upgrade-summary)))
      (when u
        (concat
         (format " | Blueprint %s (%s)"
                 (plist-get u :version)
                 (if (eq (plist-get u :source) 'declared) "declared" "inferred"))
         (when (plist-get u :pending)
           (format " | Migrations available: %d [u]"
                   (length (plist-get u :pending))))
         (when (or (> (plist-get u :templates) 0)
                   (> (plist-get u :customized) 0))
           (format " | Template: %d da aggiornare, %d personalizzati"
                   (plist-get u :templates) (plist-get u :customized))))))))

(defcustom blueprint-dashboard-milestone-width 40
  "Maximum width of the milestone title in the dashboard summary.
A longer title is cut with \"...\"; the full title stays in the
tooltip.  nil shows the title as it is."
  :type '(choice (const :tag "No limit" nil) integer)
  :group 'blueprint)

(defun blueprint--dashboard-milestone-part (milestone)
  "Return the milestone part of the dashboard summary for MILESTONE.
MILESTONE is a plist from `blueprint--milestone-summary'.  The title
is cut to `blueprint-dashboard-milestone-width'."
  (let* ((title (plist-get milestone :title))
         (shown (if (and blueprint-dashboard-milestone-width
                         (> (string-width title)
                            blueprint-dashboard-milestone-width))
                    (truncate-string-to-width
                     title blueprint-dashboard-milestone-width nil nil "...")
                  title)))
    (format " | Milestone: %s%s | open TODOs: %d"
            (propertize shown 'help-echo title)
            (if (plist-get milestone :date)
                (format " (%s)" (plist-get milestone :date))
              "")
            (plist-get milestone :open))))

(defun blueprint--dashboard-summary-line ()
  "Return the summary shown in the dashboard mode line.
Health of the whole document, number of components and of other
document files, active filters, the project version with the
migrations available (`blueprint-dashboard-show-version') and -- when
a milestone file exists at the root (`blueprint-milestone-files') --
the next open milestone and the count of open TODO items.  The
milestone comes last, cut to `blueprint-dashboard-milestone-width':
its title is free text and in a narrow window it would push the
version out of sight."
  (let* ((units (blueprint--document-units))
         (milestone (blueprint--milestone-summary)))
    (concat
     (format " Health: %d | Components: %d | Other files: %d%s%s"
             (blueprint-health-score)
             (cl-count 'component units :key (lambda (u) (plist-get u :kind)))
             (cl-count 'part units :key (lambda (u) (plist-get u :kind)))
             (if blueprint-dashboard-focus " [FOCUS]" "")
             (if blueprint-dashboard-out-of-scope-only " [OUT-OF-SCOPE]" ""))
     (blueprint--dashboard-version-part)
     (when milestone
       (blueprint--dashboard-milestone-part milestone)))))

(defun blueprint-dashboard-refresh ()
  "Refresh the dashboard buffer."
  (interactive)
  (blueprint--invalidate-cache)
  (setq tabulated-list-entries (blueprint--dashboard-entries))
  (tabulated-list-print t)
  (setq mode-line-process (blueprint--dashboard-summary-line))
  (force-mode-line-update))

(defun blueprint-dashboard-toggle-focus ()
  "Toggle focus mode (show only components with open markers)."
  (interactive)
  (setq blueprint-dashboard-focus (not blueprint-dashboard-focus))
  (blueprint-dashboard-refresh)
  (message "Focus mode %s" (if blueprint-dashboard-focus "ON" "OFF")))

(defun blueprint-dashboard-toggle-out-of-scope ()
  "Toggle the out-of-scope filter (show only out-of-scope/tbd components)."
  (interactive)
  (setq blueprint-dashboard-out-of-scope-only
        (not blueprint-dashboard-out-of-scope-only))
  (blueprint-dashboard-refresh)
  (message "Out-of-scope filter %s"
           (if blueprint-dashboard-out-of-scope-only "ON" "OFF")))

;;;###autoload
(defun blueprint-dashboard ()
  "Open the Blueprint project dashboard."
  (interactive)
  (blueprint--root)  ; ensure we're in a project
  (let ((buf (get-buffer-create "*Blueprint*")))
    (with-current-buffer buf
      (blueprint-dashboard-mode)
      (blueprint-dashboard-refresh))
    (switch-to-buffer buf)))

;;;###autoload
(defun blueprint-focus ()
  "Open the Blueprint dashboard in focus mode."
  (interactive)
  (setq blueprint-dashboard-focus t)
  (blueprint-dashboard))

;;;###autoload
(defun blueprint-out-of-scope-view ()
  "Open the Blueprint dashboard filtered to out-of-scope/tbd components."
  (interactive)
  (setq blueprint-dashboard-out-of-scope-only t)
  (blueprint-dashboard))

(defun blueprint--dashboard-svg-generate (&optional root)
  "Generate the health-colored dependency SVG of the project at ROOT.
Writes dashboard.svg at the project root and returns its path.
Signals `user-error' when Graphviz (dot) is missing.  The rendering
is shared by `blueprint-dashboard-svg' and the live preview
\(`blueprint-preview-mode')."
  (unless (executable-find "dot")
    (user-error "Graphviz (dot) not found; install it to generate SVG dashboards"))
  (let* ((root (or root (blueprint--root)))
         ;; The component and health lookups below resolve the project
         ;; from `default-directory': bind it, so ROOT is honoured.
         (default-directory (file-name-as-directory root))
         (dot-file (expand-file-name "dashboard.dot" root))
         (svg-file (expand-file-name "dashboard.svg" root))
         (comps (blueprint--components))
         (lines '()))
    (push "digraph Blueprint {" lines)
    (push "  rankdir=LR;" lines)
    (push "  node [shape=box, style=filled, fontname=\"sans-serif\"];" lines)
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (color (blueprint--component-health-color id))
              (deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
         (push (format "  %s [label=%s, fillcolor=\"%s\"];"
                       (blueprint--dot-id id) (blueprint--dot-id id) color)
               lines)
         (when deps-str
           (dolist (dep (split-string deps-str))
             (push (format "  %s -> %s;"
                           (blueprint--dot-id id) (blueprint--dot-id dep))
                   lines)))))
     comps)
    (push "}" lines)
    (with-temp-file dot-file
      (insert (mapconcat #'identity (nreverse lines) "\n")))
    (blueprint--dot-render dot-file svg-file)))

;;;###autoload
(defun blueprint-dashboard-svg ()
  "Generate an SVG overview of the project using Graphviz.
Each component is a node colored by its health score over its
documents in master.org (see `blueprint--component-health-color'):
red below 50, yellow below `blueprint-delivery-score-threshold' (80),
green otherwise, grey when master.org
includes none of its documents.  Edges are the dependencies.  Writes
dashboard.svg to the project root, shows it in the *Blueprint Graph*
buffer and returns its path."
  (interactive)
  (let ((svg-file (blueprint--dashboard-svg-generate)))
    (blueprint--show-svg-file svg-file "*Blueprint Graph*")
    svg-file))

(provide 'blueprint-dashboard)
;;; blueprint-dashboard.el ends here
