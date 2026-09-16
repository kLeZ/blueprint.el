;;; blueprint-dashboard.el --- Magit-style dashboard for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Provides a `tabulated-list-mode' dashboard showing all components with
;; metrics (questions, TBDs, FIXMEs, lines, status).  Supports focus mode
;; to filter to components needing attention, and an SVG dashboard
;; overview via Graphviz.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)

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

(defun blueprint--component-status (questions tbds fixmes)
  "Return a status string based on QUESTIONS, TBDS, and FIXMES counts."
  (cond
   ((> fixmes 0) "FIXME")
   ((> questions 2) "NEEDS-WORK")
   ((> (+ questions tbds) 0) "IN-PROGRESS")
   (t "OK")))

(defun blueprint--dashboard-entries ()
  "Build tabulated-list entries for the dashboard."
  (let ((entries '()))
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (metrics (blueprint--cached-metrics
                        file #'blueprint--component-metrics))
              (questions (nth 0 metrics))
              (tbds (nth 1 metrics))
              (fixmes (nth 2 metrics))
              (owner (or (blueprint--org-keyword file "BLUEPRINT_OWNER") ""))
              (tech (or (blueprint--org-keyword file "BLUEPRINT_TECH") ""))
              (scope (blueprint--component-scope-status id))
              (status (blueprint--component-status questions tbds fixmes))
              (has-markers (> (+ questions tbds fixmes) 0)))
         (when (and (or (not blueprint-dashboard-focus) has-markers)
                    (or (not blueprint-dashboard-out-of-scope-only)
                        (not (string= scope "in-scope"))))
           (push (list id (vector id
                                  owner
                                  tech
                                  scope
                                  (number-to-string questions)
                                  (number-to-string tbds)
                                  (number-to-string fixmes)
                                  status))
                 entries))))
     (blueprint--components))
    (sort entries (lambda (a b) (string< (car a) (car b))))))

(defvar blueprint-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'blueprint-dashboard-visit)
    (define-key map (kbd "g") #'blueprint-dashboard-refresh)
    (define-key map (kbd "F") #'blueprint-dashboard-toggle-focus)
    (define-key map (kbd "O") #'blueprint-dashboard-toggle-out-of-scope)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `blueprint-dashboard-mode'.")

(define-derived-mode blueprint-dashboard-mode tabulated-list-mode "Blueprint"
  "Major mode for the Blueprint project dashboard."
  (setq tabulated-list-format
        [("Component" 25 t)
         ("Owner" 15 t)
         ("Tech" 15 t)
         ("Scope" 13 t)
         ("Questions" 10 t)
         ("TBDs" 6 t)
         ("FIXMEs" 8 t)
         ("Status" 12 t)])
  (tabulated-list-init-header))

(defun blueprint-dashboard-visit ()
  "Open the component at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (when id
      (find-file (blueprint--component-file id)))))

(defun blueprint-dashboard-refresh ()
  "Refresh the dashboard buffer."
  (interactive)
  (blueprint--invalidate-cache)
  (setq tabulated-list-entries (blueprint--dashboard-entries))
  (tabulated-list-print t)
  (let ((score (blueprint-health-score)))
    (setq header-line-format
          (format " Blueprint Dashboard | Health: %d | Components: %d%s%s"
                  score
                  (hash-table-count (blueprint--components))
                  (if blueprint-dashboard-focus " [FOCUS]" "")
                  (if blueprint-dashboard-out-of-scope-only " [OUT-OF-SCOPE]" "")))))

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

;;;###autoload
(defun blueprint-dashboard-svg ()
  "Generate an SVG overview of the project using Graphviz.
Each component is a node colored by health status, with edges for
dependencies.  Writes dashboard.svg to the project root."
  (interactive)
  (unless (executable-find "dot")
    (user-error "Graphviz (dot) not found; install it to generate SVG dashboards"))
  (let* ((root (blueprint--root))
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
              (metrics (blueprint--cached-metrics
                        file #'blueprint--component-metrics))
              (questions (nth 0 metrics))
              (tbds (nth 1 metrics))
              (fixmes (nth 2 metrics))
              (total (+ questions tbds fixmes))
              (color (cond ((> fixmes 0) "#ff6b6b")
                           ((> total 3) "#ffd93d")
                           (t "#6bcb77")))
              (deps-str (with-temp-buffer
                          (when (and file (file-exists-p file))
                            (insert-file-contents file)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   "^#\\+BLUEPRINT_DEPENDS:[[:blank:]]*\\(.*\\S-\\)" nil t)
                              (match-string 1))))))
         (push (format "  %s [label=\"%s\", fillcolor=\"%s\"];" id id color) lines)
         (when deps-str
           (dolist (dep (split-string deps-str))
             (push (format "  %s -> %s;" id dep) lines)))))
     comps)
    (push "}" lines)
    (with-temp-file dot-file
      (insert (mapconcat #'identity (nreverse lines) "\n")))
    (call-process "dot" nil nil nil "-Tsvg" "-o" svg-file dot-file)
    (delete-file dot-file)
    (find-file svg-file)
    (message "Generated %s" svg-file)))

(provide 'blueprint-dashboard)
;;; blueprint-dashboard.el ends here
