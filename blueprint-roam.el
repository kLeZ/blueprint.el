;;; blueprint-roam.el --- Org-roam integration for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Optional integration with org-roam.  Registers component arc42.org
;; files as org-roam nodes, enabling backlink navigation between
;; components.  Requires org-roam to be installed.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-graph)

;; org-roam is a soft dependency: loaded with `require ... nil t' in
;; the commands below.  Its database functions are declared here so the
;; byte compiler does not warn about them.
(declare-function org-roam-db-query "ext:org-roam-db" (query &rest args))

(defun blueprint--roam-available-p ()
  "Return non-nil if org-roam is available."
  (require 'org-roam nil t))

;;;###autoload
(defun blueprint-roam-setup ()
  "Configure org-roam to include Blueprint component directories.
Adds the data directory's components/ directory to `org-roam-directory' search."
  (interactive)
  (unless (blueprint--roam-available-p)
    (user-error "Package org-roam is not installed"))
  (let ((comp-dir (blueprint--data-path "components")))
    ;; Ensure components have org-roam IDs
    (maphash
     (lambda (_id dir)
       (let ((file (expand-file-name "arc42.org" dir)))
         (when (file-exists-p file)
           (with-current-buffer (find-file-noselect file)
             (goto-char (point-min))
             (unless (re-search-forward "^:ID:" nil t)
               (goto-char (point-min))
               (when (re-search-forward "^#\\+TITLE:" nil t)
                 (end-of-line)
                 (insert (format "\n:PROPERTIES:\n:ID: %s\n:END:"
                                 (org-id-new)))))
             (save-buffer)))))
     (blueprint--components))
    (message "Blueprint components configured for org-roam in %s" comp-dir)))

;;;###autoload
(defun blueprint-roam-find ()
  "Find a Blueprint component using org-roam's node finder."
  (interactive)
  (unless (blueprint--roam-available-p)
    (user-error "Package org-roam is not installed"))
  (let* ((comps (blueprint--components))
         (names (hash-table-keys comps))
         (name (completing-read "Blueprint component: " names nil t))
         (file (blueprint--read-component-document name)))
    (when file (find-file file))))

;;; --- Semantic search on the org-roam database (9.8) ---

(defun blueprint--roam-tokens (title)
  "Split TITLE into lowercase tokens for the similarity score."
  (split-string (downcase (or title "")) "[^[:alnum:]]+" t))

(defun blueprint--roam-similarity (a-tags a-links a-title
                                       b-tags b-links b-title)
  "Return a similarity score between two components' features.
A-TAGS/A-LINKS/A-TITLE are the tags, outgoing links and title of the
first component, B-* of the second.  Shared tags and shared outgoing
links weigh 2 each, shared title tokens 1."
  (+ (* 2 (length (cl-intersection a-tags b-tags :test #'equal)))
     (* 2 (length (cl-intersection a-links b-links :test #'equal)))
     (length (cl-intersection (blueprint--roam-tokens a-title)
                              (blueprint--roam-tokens b-title)
                              :test #'equal))))

(defun blueprint--roam-node-features (file)
  "Return (TAGS LINKS TITLE) of the org-roam file node of FILE.
The file node is the level-0 node of FILE (a heading with an ID is a
node of its own, and may come first).  TAGS are the tags of that node
\(the tags table keys them by `node-id'), LINKS the destinations of
the links of every node of FILE, TITLE the title of the file node.
Every query failure degrades to empty features and a message, so a
stale database never breaks the listing."
  (let ((tags '()) (links '()) (title ""))
    (condition-case err
        (let ((node (caar (org-roam-db-query
                           [:select [id] :from nodes
                            :where (and (= file $s1) (= level 0))]
                           file))))
          (when node
            (setq tags (mapcar #'car
                               (org-roam-db-query
                                [:select [tag] :from tags
                                 :where (= node-id $s1)]
                                node))
                  links (delete-dups
                         (mapcar #'car
                                 (org-roam-db-query
                                  [:select [links:dest] :from links
                                   :inner-join nodes
                                   :on (= links:source nodes:id)
                                   :where (= nodes:file $s1)]
                                  file)))
                  title (or (caar (org-roam-db-query
                                   [:select [title] :from nodes
                                    :where (= id $s1)]
                                   node))
                            ""))))
      (error (message "Blueprint roam: database not available (%s); run org-roam-db-sync"
                      (error-message-string err))))
    (list tags links title)))

(defun blueprint--roam-shared (me other)
  "Return what features ME and OTHER have in common, for display.
Both are (TAGS LINKS TITLE) lists of `blueprint--roam-node-features'.
Returns (TAGS LINKS TOKENS): the shared tags, the shared link
destinations and the shared title tokens."
  (list (cl-intersection (nth 0 me) (nth 0 other) :test #'equal)
        (cl-intersection (nth 1 me) (nth 1 other) :test #'equal)
        (cl-intersection (blueprint--roam-tokens (nth 2 me))
                         (blueprint--roam-tokens (nth 2 other))
                         :test #'equal)))

(defun blueprint--roam-dest-label (dest)
  "Return a readable label for the link destination DEST.
An id: destination is a node ID: its node title is shown when the
database knows it, the destination itself otherwise."
  (or (ignore-errors
        (caar (org-roam-db-query
               [:select [title] :from nodes :where (= id $s1)] dest)))
      dest))

;;;###autoload
(defun blueprint-roam-similar (&optional component)
  "Rank the components most similar to COMPONENT via org-roam.
Similarity counts shared tags, shared outgoing links and shared title
tokens (see `blueprint--roam-similarity').  The result opens in a
buffer sorted by score, best first; the last column lists what the
two components have in common."
  (interactive
   (list (when current-prefix-arg
           (completing-read "Component: "
                            (hash-table-keys (blueprint--components))
                            nil t))))
  (unless (blueprint--roam-available-p)
    (user-error "Package org-roam is not installed"))
  (let* ((comps (blueprint--components))
         (id (or component
                 (completing-read "Component: "
                                  (hash-table-keys comps) nil t)))
         (dir (gethash id comps))
         (arc (and dir (expand-file-name "arc42.org" dir))))
    (unless arc (user-error "Component %s not found" id))
    (let* ((me (blueprint--roam-node-features arc))
           (scores '()))
      (maphash (lambda (other other-dir)
                 (unless (string= other id)
                   (let* ((other-arc (expand-file-name "arc42.org" other-dir))
                          (feats (blueprint--roam-node-features other-arc))
                          (score (blueprint--roam-similarity
                                  (nth 0 me) (nth 1 me) (nth 2 me)
                                  (nth 0 feats) (nth 1 feats) (nth 2 feats))))
                     (when (> score 0)
                       (push (list other score (blueprint--roam-shared me feats))
                             scores)))))
               comps)
      (setq scores (sort scores (lambda (a b)
                                  (or (> (cadr a) (cadr b))
                                      (and (= (cadr a) (cadr b))
                                           (string< (car a) (car b)))))))
      (if (null scores)
          (message "No similar component found (all scores are 0)")
        (with-current-buffer (get-buffer-create "*Blueprint Similar*")
          (setq tabulated-list-format
                [("Component" 30 t) ("Score" 8 t) ("In comune" 50)])
          (setq tabulated-list-entries
                (mapcar (lambda (s)
                          (let ((shared (nth 2 s)))
                            (list (car s)
                                  (vector (car s)
                                          (number-to-string (cadr s))
                                          (format "tag: %s | link: %s | titolo: %s"
                                                  (string-join (nth 0 shared) ", ")
                                                  (mapconcat #'blueprint--roam-dest-label
                                                             (nth 1 shared) ", ")
                                                  (string-join (nth 2 shared) ", "))))))
                        scores))
          (tabulated-list-mode)
          (tabulated-list-init-header)
          (tabulated-list-print)
          (switch-to-buffer (current-buffer)))
        scores))))

(defun blueprint--roam-linked-files (file)
  "Return the files the org-roam nodes of FILE link to.
In the org-roam database the source of a link is a node ID, not a
file, and the destination of an id: link is a node ID too: the links
are joined with the nodes of FILE and every id: destination is mapped
back to the file of its node.  file: links keep their path, expanded
against the directory of FILE.  Other link types (http, ...) are not
files and are left out."
  (let ((files '()))
    (dolist (row (org-roam-db-query
                  [:select [links:dest links:type] :from links
                   :inner-join nodes :on (= links:source nodes:id)
                   :where (= nodes:file $s1)]
                  file))
      (pcase-let ((`(,dest ,type) row))
        (cond
         ((equal type "id")
          (dolist (target (org-roam-db-query
                           [:select [file] :from nodes :where (= id $s1)]
                           dest))
            (push (car target) files)))
         ((equal type "file")
          (push (expand-file-name dest (file-name-directory file)) files)))))
    (delete-dups (nreverse files))))

;;;###autoload
(defun blueprint-roam-clusters ()
  "Show the clusters of components joined by dependencies or links.
The clusters are the connected components of the graph that joins two
components when one depends on the other (#+BLUEPRINT_DEPENDS:) or
org-roam knows a link between them (the latter only with org-roam
installed; without it the clusters follow the dependencies alone)."
  (interactive)
  (let* ((deps (blueprint--graph-deps))
         (links '()))
    ;; `blueprint--roam-available-p' loads org-roam when it is there.
    (when (blueprint--roam-available-p)
      (condition-case err
          (let ((comps (blueprint--components)))
            (maphash (lambda (id dir)
                       (let ((file (expand-file-name "arc42.org" dir)))
                         (dolist (dest (blueprint--roam-linked-files file))
                           (let ((other (blueprint--component-of-file dest comps)))
                             (when (and other (not (string= other id)))
                               (push (cons id (list other)) links))))))
                     comps))
        (error (message "Blueprint roam: links not available (%s); clusters from the dependencies only"
                        (error-message-string err)))))
    (let* ((merged (append deps links))
           (clusters (blueprint--dependency-clusters merged))
           (comps (blueprint--components)))
      (with-current-buffer (get-buffer-create "*Blueprint Clusters*")
        ;; The buffer is read-only from the previous run (special-mode).
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "Cluster di dipendenze e link (%d componenti)\n\n"
                          (hash-table-count comps)))
          (dolist (c clusters)
            (insert (format "- %s\n" (mapconcat #'identity c ", ")))))
        (goto-char (point-min))
        (special-mode)
        (pop-to-buffer (current-buffer)))
      clusters)))

(provide 'blueprint-roam)
;;; blueprint-roam.el ends here
