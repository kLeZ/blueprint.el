;;; blueprint-test-e2e.el --- End-to-end tests for Blueprint  -*- lexical-binding:t; -*-

;;; Commentary:

;; End-to-end tests that simulate a full project lifecycle:
;; initialization, component creation with dependencies, C4 generation,
;; health scoring, linting, sync, ADR management, and content commands.
;; These tests exercise multiple modules together and catch integration
;; issues that unit tests miss.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)
(require 'blueprint-lint)
(require 'blueprint-adr)
(require 'blueprint-sync)
(require 'blueprint-glossary)
(require 'blueprint-references)
(require 'blueprint-questions)
(require 'blueprint-risks)
(require 'blueprint-migrate)

;;; --- Full project lifecycle ---

(ert-deftest blueprint-test-e2e/full-init-and-inspect ()
  "Initialize a project, add components, and verify the project structure."
  (blueprint-test--with-project
    ;; Project structure already initialized by the macro.
    ;; Verify root is detected.
    (should (stringp (blueprint--root)))
    ;; Should start with no components.
    (should (= 0 (hash-table-count (blueprint--components))))))

(ert-deftest blueprint-test-e2e/component-lifecycle ()
  "Add, inspect, rename, and delete a component."
  (blueprint-test--with-project
    ;; Add
    (blueprint-add-component "order-service")
    (should (gethash "order-service" (blueprint--components)))
    (should (file-exists-p (blueprint--component-file "order-service")))
    ;; Rename
    (blueprint-rename-component "order-service" "order-svc")
    (should (gethash "order-svc" (blueprint--components)))
    (should-not (gethash "order-service" (blueprint--components)))
    ;; Delete
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (blueprint-delete-component "order-svc"))
    (should (= 0 (hash-table-count (blueprint--components))))))

(ert-deftest blueprint-test-e2e/multi-component-c4 ()
  "A realistic three-tier architecture produces correct C4 and health output."
  (blueprint-test--with-project
    (let ((proj default-directory))
    ;; Three-tier: frontend → backend → database
    (blueprint-test--write-component
     "frontend"
     (concat "#+TITLE: frontend\n"
             "#+BLUEPRINT_DEPENDS: backend\n\n"
             "* Introduction\n\nReact SPA.\n"
             "* Context and Scope\n\nBrowser-based UI.\n"
             "* Constraints\n\nMust support IE11.\n"
             "* Solution Strategy\n\nSPA with REST calls.\n"
             "* Building Blocks\n\nReact components.\n"
             "* Runtime Behavior\n\nSingle page navigation.\n"
             "* Deployment\n\nS3 + CloudFront.\n"
             "* Responsibility\n\nFrontend team.\n"
             "* Risks\n\nBrowser compatibility.\n"
             "* Open Questions\n\nNone.\n"
             "* Diagrams\n\nSee c4.puml.\n"))
    (blueprint-test--write-component
     "backend"
     (concat "#+TITLE: backend\n"
             "#+BLUEPRINT_DEPENDS: database\n\n"
             "* Introduction\n\nNode.js REST API.\n"
             "* Context and Scope\n\nHandles all business logic.\n"
             "* Constraints\n\nStateless.\n"
             "* Solution Strategy\n\nExpress.js with JWT auth.\n"
             "* Building Blocks\n\nControllers and services.\n"
             "* Runtime Behavior\n\nRequest/response cycle.\n"
             "* Deployment\n\nECS Fargate.\n"
             "* Responsibility\n\nBackend team.\n"
             "* Risks\n\nSingle point of failure for auth. TBD\n"
             "* Open Questions\n\nNone.\n"
             "* Diagrams\n\nSee c4.puml.\n"))
    (blueprint-test--write-component
     "database"
     (concat "#+TITLE: database\n"
             "#+BLUEPRINT_DEPENDS:\n\n"
             "* Introduction\n\nPostgreSQL 15.\n"
             "* Context and Scope\n\nPrimary data store.\n"
             "* Constraints\n\nACID compliance required.\n"
             "* Solution Strategy\n\nManaged RDS instance.\n"
             "* Building Blocks\n\nSchemas and indexes.\n"
             "* Runtime Behavior\n\nRead/write operations.\n"
             "* Deployment\n\nRDS Multi-AZ.\n"
             "* Responsibility\n\nDBA team.\n"
             "* Risks\n\nNo backup strategy currently.\n"
             "* Open Questions\n\nFIXME: Define backup rotation.\n"
             "* Diagrams\n\nSee c4.puml.\n"))
    (blueprint--invalidate-cache)

    ;; C4 generation
    (blueprint-generate-c4)
    (let ((c4-content (blueprint-test--read-file
                       (expand-file-name "c4.puml" default-directory))))
      (should (string-match-p "Container(frontend" c4-content))
      (should (string-match-p "Container(backend" c4-content))
      (should (string-match-p "Container(database" c4-content))
      (should (string-match-p "Rel(frontend, backend" c4-content))
      (should (string-match-p "Rel(backend, database" c4-content)))

    ;; Health: backend has 1 TBD (2 points), database has 1 FIXME (4)
    (let* ((stats (blueprint--health-component-stats))
           (penalty (apply #'+ (mapcar #'cadr stats)))
           (words (apply #'+ (mapcar #'caddr stats))))
      (should (= 6 penalty))
      (should (= (blueprint--health-score-from penalty words)
                 (blueprint-health-score)))
      (should (< 0 (blueprint-health-score) 100)))

    ;; Lint: frontend should have no heading warnings; database should
    ;; have no dangling deps
    (let ((lint-warnings (blueprint--lint-component
                          "frontend"
                          (blueprint--component-file "frontend"))))
      (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                           lint-warnings)))
    (let ((db-warns (blueprint--lint-component
                     "database"
                     (blueprint--component-file "database"))))
      (should-not (cl-some (lambda (w) (string-match-p "unknown component" w))
                           db-warns)))

    ;; Risks: database has "no backup" → "No backup strategy"
    (let ((db-risks (blueprint--detect-risks
                     (blueprint--component-file "database"))))
      (should (member "No backup strategy"
                      (mapcar (lambda (r) (plist-get r :risk)) db-risks))))

    ;; Risks: backend has "single point of failure"
    (let ((be-risks (blueprint--detect-risks
                     (blueprint--component-file "backend"))))
      (should (member "Single point of failure detected"
                      (mapcar (lambda (r) (plist-get r :risk)) be-risks)))))))

(ert-deftest blueprint-test-e2e/sync-and-adrs ()
  "Master sync and ADR management work end-to-end."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "auth")
      (blueprint-test--write-component "api")

      ;; Sync master
      (blueprint-sync)
      (let ((master (blueprint-test--read-file
                     (expand-file-name "master.org" proj))))
        (should (string-match-p "auth" master))
        (should (string-match-p "api" master)))

      ;; Create two ADRs — save proj before, since blueprint-adr-new calls find-file
      (blueprint-adr-new "Use JWT for authentication")
      (blueprint-adr-new "Adopt hexagonal architecture")
      ;; Both ADRs must be in the consolidated adr.org file (single-file model)
      (let* ((adr-file (expand-file-name ".blueprint/adr.org" proj))
             (content (blueprint-test--read-file adr-file)))
        (should (string-match-p "ADR 0001.*JWT" content))
        (should (string-match-p "ADR 0002.*hexagonal" content))
        ;; adr.org lives directly in .blueprint/, not in a subdirectory
        (should (file-exists-p adr-file))))))

(ert-deftest blueprint-test-e2e/glossary-and-references ()
  "Glossary and reference management work end-to-end."
  (blueprint-test--with-project
    (blueprint-glossary-add "SLA" "Service Level Agreement" "contract-2024")
    (blueprint-glossary-add "RTO" "Recovery Time Objective" "disaster-plan")
    (blueprint-reference-add "Architecture Review Board Notes" "document"
                             "Q4 review session")
    (blueprint-reference-add "CTO Interview" "interview" "Strategic direction")

    (let ((glossary (blueprint-test--read-file
                     (expand-file-name "glossary.org" default-directory)))
          (refs (blueprint-test--read-file
                 (expand-file-name "references.org" default-directory))))
      (should (string-match-p "SLA" glossary))
      (should (string-match-p "RTO" glossary))
      (should (string-match-p "Architecture Review Board" refs))
      (should (string-match-p "CTO Interview" refs)))))

(ert-deftest blueprint-test-e2e/questions-workflow ()
  "Adding questions updates component files correctly."
  (blueprint-test--with-project
    (blueprint-test--write-component "payment")
    (blueprint-add-question "payment" "Who approves card transactions?")
    (blueprint-add-question "payment" "What is the retry strategy on failure?")

    (let ((content (blueprint-test--read-file
                    (blueprint--component-file "payment"))))
      (should (string-match-p "card transactions" content))
      (should (string-match-p "retry strategy" content)))

    ;; Health: 2 QUESTIONs weigh 6 penalty points
    (should (= 6 (nth 1 (assoc "payment" (blueprint--health-component-stats)))))
    (should (< (blueprint-health-score) 100))))

(ert-deftest blueprint-test-e2e/template-migration ()
  "Template migration copies system templates to the project."
  (blueprint-test--with-project
    (blueprint-template-migrate)
    (let ((proj-tmpl (expand-file-name ".blueprint/templates" default-directory)))
      (should (file-directory-p proj-tmpl))
      (should (file-exists-p (expand-file-name "component.org" proj-tmpl))))))

(ert-deftest blueprint-test-e2e/rename-updates-all-deps ()
  "Renaming a component updates all BLUEPRINT_DEPENDS references across files."
  (blueprint-test--with-project
    (blueprint-test--write-component "service-old")
    (blueprint-test--write-component
     "consumer-a"
     "#+TITLE: consumer-a\n#+BLUEPRINT_DEPENDS: service-old\n\n* Introduction\n\nText.\n")
    (blueprint-test--write-component
     "consumer-b"
     "#+TITLE: consumer-b\n#+BLUEPRINT_DEPENDS: service-old\n\n* Introduction\n\nText.\n")

    (blueprint-rename-component "service-old" "service-new")

    (let ((content-a (blueprint-test--read-file
                      (blueprint--component-file "consumer-a")))
          (content-b (blueprint-test--read-file
                      (blueprint--component-file "consumer-b"))))
      (should (string-match-p "service-new" content-a))
      (should-not (string-match-p "\\bservice-old\\b" content-a))
      (should (string-match-p "service-new" content-b))
      (should-not (string-match-p "\\bservice-old\\b" content-b)))))

(provide 'blueprint-test-e2e)
;;; blueprint-test-e2e.el ends here
