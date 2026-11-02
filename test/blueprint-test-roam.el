;;; blueprint-test-roam.el --- Tests for blueprint-roam.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the org-roam integration.  The pure logic (dependency
;; clusters, similarity score, title tokens) is tested for real; the
;; commands that need the org-roam database are skipped when org-roam
;; is not installed (as in CI).

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-roam)
(require 'blueprint-graph)

;;; --- Pure logic ---

(ert-deftest blueprint-test-roam/tokens-lowercase-and-split ()
  "Titles split into lowercase alphanumeric tokens."
  (should (equal (blueprint--roam-tokens "Order Service API")
                 '("order" "service" "api")))
  (should (null (blueprint--roam-tokens nil))))

(ert-deftest blueprint-test-roam/similarity-weights ()
  "Shared tags and links weigh 2, shared title tokens 1."
  (should (= 5 (blueprint--roam-similarity
                '("payments") '("db") "Order Service"
                '("payments") '("db") "Order Management")))
  (should (= 1 (blueprint--roam-similarity
                nil nil "Order Service" nil nil "Order Management")))
  (should (zerop (blueprint--roam-similarity
                  nil nil "Cassa" nil nil "Warehouse"))))

(ert-deftest blueprint-test-graph/dependency-clusters ()
  "Components joined by a dependency chain share a cluster; isolated
components are clusters of their own; unknown deps are ignored."
  (let* ((deps '(("api" . ("payments" "ghost"))
                 ("payments" . ("db"))
                 ("db" . ())
                 ("frontend" . ("api"))
                 ("warehouse" . ())))
         (clusters (blueprint--dependency-clusters deps)))
    (should (= 2 (length clusters)))
    ;; Largest cluster first, ids alphabetical inside.
    (should (equal (car clusters) '("api" "db" "frontend" "payments")))
    (should (equal (cadr clusters) '("warehouse")))))

(ert-deftest blueprint-test-graph/dependency-clusters-empty ()
  "No dependencies: every component is its own cluster."
  (should (null (blueprint--dependency-clusters nil)))
  (should (equal (blueprint--dependency-clusters '(("a" . nil) ("b" . nil)))
                 '(("a") ("b")))))

;;; --- Commands (need org-roam) ---

(ert-deftest blueprint-test-roam/similar-requires-org-roam ()
  "Without org-roam the command says so instead of erroring obscurely."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (if (blueprint--roam-available-p)
        (ert-skip "org-roam installed: the graceful-error path is not exercised")
      (should-error (blueprint-roam-similar "svc") :type 'user-error))))

(ert-deftest blueprint-test-roam/clusters-work-without-org-roam ()
  "The clusters command works with the dependencies alone when
org-roam is missing, and lists every component."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "api" (concat "#+TITLE: api\n#+BLUEPRINT_DEPENDS: payments\n\n"
                   "* Introduction\n"))
    (blueprint-test--write-component
     "payments" (concat "#+TITLE: payments\n#+BLUEPRINT_DEPENDS: db\n\n"
                        "* Introduction\n"))
    (blueprint-test--write-component "db" "#+TITLE: db\n")
    (blueprint-test--write-component "warehouse" "#+TITLE: warehouse\n")
    (if (blueprint--roam-available-p)
        (ert-skip "org-roam installed: dependencies-only path not exercised")
      (let ((clusters (blueprint-roam-clusters)))
        (should (= 2 (length clusters)))
        (should (equal (car clusters) '("api" "db" "payments")))))))

(ert-deftest blueprint-test-roam/clusters-follow-roam-links ()
  "Roam links join clusters: the links of a component are found
through its nodes (a link's source is a node ID, not a file) and an
id: destination is mapped back to its node's file.  The database is
stubbed, so the test runs without org-roam."
  (blueprint-test--with-project
    (blueprint-test--write-component "api" "#+TITLE: api\n")
    (blueprint-test--write-component "billing" "#+TITLE: billing\n")
    (blueprint-test--write-component "warehouse" "#+TITLE: warehouse\n")
    (let* ((comps (blueprint--components))
           (api (expand-file-name "arc42.org" (gethash "api" comps)))
           (billing (expand-file-name "arc42.org" (gethash "billing" comps)))
           (queries '()))
      (cl-letf (((symbol-function 'blueprint--roam-available-p) (lambda () t))
                ((symbol-function 'org-roam-db-query)
                 (lambda (query &rest args)
                   (push (cons query args) queries)
                   (cond
                    ;; Links of the nodes of a file: api links billing.
                    ((memq :inner-join (append query nil))
                     (if (equal (car args) api)
                         '(("node-billing" "id") ("https://x" "https"))
                       nil))
                    ;; File of a node.
                    ((equal (car args) "node-billing")
                     (list (list billing)))
                    (t nil)))))
        (let ((clusters (blueprint-roam-clusters)))
          (should (equal (car clusters) '("api" "billing")))
          (should (member '("warehouse") clusters))
          ;; The links query never matched a file path against
          ;; links.source.
          (should-not (seq-find (lambda (q)
                                  (and (not (memq :inner-join (append (car q) nil)))
                                       (member 'source (append (car q) nil))))
                                queries)))))))

(defun blueprint-test-roam--query-symbols (query)
  "Return the symbols of the emacsql QUERY vector, flattened."
  (flatten-tree (mapcar (lambda (x) (if (vectorp x) (append x nil) x))
                        (append query nil))))

(ert-deftest blueprint-test-roam/similar-uses-roam-schema ()
  "Similarity reads the org-roam schema as it is: the file node is the
level-0 node, tags are keyed by node-id, links by source node.  The
\"In comune\" column lists only what the two components share.  The
database is stubbed, so the test runs without org-roam."
  (blueprint-test--with-project
    (blueprint-test--write-component "orders" "#+TITLE: orders\n")
    (blueprint-test--write-component "order-history" "#+TITLE: order-history\n")
    (blueprint-test--write-component "warehouse" "#+TITLE: warehouse\n")
    (let* ((comps (blueprint--components))
           (file-of (lambda (id) (expand-file-name "arc42.org" (gethash id comps))))
           (node-of (lambda (f) (seq-find (lambda (c) (equal (funcall file-of c) f))
                                          '("orders" "order-history" "warehouse"))))
           (data '(("orders" ("payments" "core") ("db-node") "Order Service")
                   ("order-history" ("payments" "archive") ("db-node") "Order History")
                   ("warehouse" ("logistics") nil "Warehouse"))))
      (cl-letf (((symbol-function 'blueprint--roam-available-p) (lambda () t))
                ((symbol-function 'org-roam-db-query)
                 (lambda (query &rest args)
                   (let ((syms (blueprint-test-roam--query-symbols query))
                         (arg (car args)))
                     (cond
                      ((memq 'node-id syms)
                       (mapcar #'list (nth 1 (assoc arg data))))
                      ((memq 'tags syms) (error "no such column: node"))
                      ((memq 'links:dest syms)
                       (mapcar #'list (nth 2 (assoc (funcall node-of arg) data))))
                      ((and (memq 'level syms) (memq 'id syms))
                       (list (list (funcall node-of arg))))
                      ((memq 'title syms)
                       (if (equal arg "db-node")
                           '(("Database"))
                         (list (list (nth 3 (assoc arg data))))))
                      (t nil))))))
        (let ((scores (blueprint-roam-similar "orders")))
          ;; tag payments (2) + link db-node (2) + token "order" (1)
          (should (equal (mapcar (lambda (s) (list (car s) (cadr s))) scores)
                         '(("order-history" 5))))
          (with-current-buffer "*Blueprint Similar*"
            (let ((text (buffer-string)))
              (should (string-match-p "tag: payments |" text))
              (should (string-match-p "link: Database" text))
              (should (string-match-p "titolo: order" text))
              (should-not (string-match-p "archive" text)))))))))

(provide 'blueprint-test-roam)
;;; blueprint-test-roam.el ends here
