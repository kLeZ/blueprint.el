;;; blueprint-graph.el --- Dependency graph for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Generates dependency graphs in PlantUML or Graphviz (dot) format,
;; with nodes colored by component health score (Graphviz only),
;; computed over the documents of each component that master.org
;; includes.  The colored overview without choosing a backend is
;; `blueprint-dashboard-svg'.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)

(defcustom blueprint-graph-backend 'plantuml
  "Backend for dependency graph generation.
Supported values: plantuml, graphviz."
  :type '(choice (const :tag "PlantUML" plantuml)
                 (const :tag "Graphviz (dot)" graphviz))
  :group 'blueprint)

(defun blueprint--graph-deps ()
  "Return an alist of (COMPONENT . (DEP ...)) for all components."
  (let ((result '()))
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (deps-str (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))
              (deps (when (and deps-str (not (string-blank-p deps-str)))
                      (split-string deps-str))))
         (push (cons id deps) result)))
     (blueprint--components))
    result))

(defun blueprint--graph-health-color (id)
  "Return a color string for component ID based on its health score.
The score covers the documents of the component that master.org
includes, with the weights of `blueprint-health-score'; see
`blueprint--component-health-color'."
  (blueprint--component-health-color id))

(defun blueprint--dependency-clusters (deps-alist)
  "Return the connected clusters of DEPS-ALIST, an alist (ID . DEPS).
A list of lists of ids: two components belong to the same cluster when
a chain of dependencies joins them, and a component with no
dependencies is a cluster of its own.  Clusters are sorted largest
first, each cluster's ids alphabetically.  A dependency on an unknown
component (not a key of DEPS-ALIST) is ignored: it dangles -- the lint
flags it -- and joins nothing."
  (let ((parent (make-hash-table :test 'equal))
        (ids (delete-dups (mapcar #'car deps-alist))))
    (dolist (id ids) (puthash id id parent))
    (cl-labels ((find-root (x)
                  (while (not (equal (gethash x parent) x))
                    (setq x (gethash x parent)))
                  x))
      (dolist (entry deps-alist)
        (dolist (dep (cdr entry))
          (when (gethash dep parent)
            (let ((ra (find-root (car entry)))
                  (rb (find-root dep)))
              (unless (equal ra rb)
                (puthash ra rb parent))))))
      (let ((groups (make-hash-table :test 'equal)))
        (dolist (id ids)
          (let ((root (find-root id)))
            (puthash root (cons id (gethash root groups)) groups)))
        (let ((clusters (mapcar (lambda (cluster) (sort cluster #'string<))
                                (hash-table-values groups))))
          ;; Total order: largest first, then by the smallest id, so
          ;; the result does not depend on the hash iteration order.
          (sort clusters
                (lambda (a b)
                  (or (> (length a) (length b))
                      (and (= (length a) (length b))
                           (string< (car a) (car b)))))))))))

(defun blueprint--graph-plantuml (deps root)
  "Generate a PlantUML dependency diagram from DEPS in ROOT."
  (let ((outfile (expand-file-name "component-deps.puml" root)))
    (with-temp-file outfile
      (insert "@startuml\n")
      (insert "!include C4_Component.puml\n\n")
      (dolist (entry deps)
        (let ((id (car entry)))
          (insert (format "Component(%s, \"%s\", \"\")\n" id id))))
      (insert "\n")
      (dolist (entry deps)
        (let ((id (car entry)))
          (dolist (dep (cdr entry))
            (insert (format "Rel(%s, %s, \"uses\")\n" id dep)))))
      (insert "\n@enduml\n"))
    outfile))

(defun blueprint--graph-graphviz (deps root)
  "Generate a Graphviz dependency diagram from DEPS in ROOT."
  (let ((dot-file (expand-file-name "component-deps.dot" root))
        (svg-file (expand-file-name "component-deps.svg" root)))
    (with-temp-file dot-file
      (insert "digraph Dependencies {\n")
      (insert "  rankdir=LR;\n")
      (insert "  node [shape=box, style=filled, fontname=\"sans-serif\"];\n\n")
      (dolist (entry deps)
        (let ((id (car entry))
              (color (blueprint--graph-health-color (car entry))))
          (insert (format "  %s [label=%s, fillcolor=\"%s\"];\n"
                          (blueprint--dot-id id) (blueprint--dot-id id)
                          color))))
      (insert "\n")
      (dolist (entry deps)
        (dolist (dep (cdr entry))
          (insert (format "  %s -> %s;\n"
                          (blueprint--dot-id (car entry))
                          (blueprint--dot-id dep)))))
      (insert "}\n"))
    (if (executable-find "dot")
        (blueprint--dot-render dot-file svg-file)
      dot-file)))

;;;###autoload
(defun blueprint-dependency-graph ()
  "Generate a dependency graph for the project.
Uses `blueprint-graph-backend' to select the output format.  Only the
Graphviz backend colors the components by health score; with the
default PlantUML backend the result is the .puml source.  For the
colored overview regardless of the backend see
`blueprint-dashboard-svg'."
  (interactive)
  (let* ((root (blueprint--root))
         (deps (blueprint--graph-deps))
         (outfile (pcase blueprint-graph-backend
                    ('plantuml (blueprint--graph-plantuml deps root))
                    ('graphviz (blueprint--graph-graphviz deps root))
                    (_ (user-error "Unknown graph backend: %s"
                                   blueprint-graph-backend)))))
    (if (string-suffix-p ".svg" outfile)
        (blueprint--show-svg-file outfile "*Blueprint Dependency Graph*")
      (find-file outfile)
      (message "Generated %s" outfile))))

(provide 'blueprint-graph)
;;; blueprint-graph.el ends here
