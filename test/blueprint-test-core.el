;;; blueprint-test-core.el --- Tests for blueprint-core.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Unit tests for project root detection, component enumeration,
;; template resolution, metrics cache, and CRUD operations.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)

;;; --- blueprint--root ---

(ert-deftest blueprint-test-root/found ()
  "Root is detected when .blueprint/ exists in the working directory."
  (blueprint-test--with-project
    (let ((root (blueprint--root)))
      (should (stringp root))
      (should (file-directory-p (expand-file-name ".blueprint" root))))))

(ert-deftest blueprint-test-root/not-found ()
  "An error is raised when no .blueprint/ directory exists."
  (let* ((tmpdir (make-temp-file "blueprint-no-project-" t))
         (default-directory (file-name-as-directory tmpdir)))
    (unwind-protect
        (should-error (blueprint--root) :type 'user-error)
      (delete-directory tmpdir t))))

(ert-deftest blueprint-test-root/subdirectory ()
  "Root is found even when `default-directory' is a subdirectory of the project."
  (blueprint-test--with-project
    (let* ((subdir (expand-file-name "sub/dir" default-directory))
           (default-directory (progn (make-directory subdir t)
                                     (file-name-as-directory subdir))))
      (should (stringp (blueprint--root))))))

;;; --- blueprint--components ---

(ert-deftest blueprint-test-components/empty ()
  "Empty hash table returned when no components exist."
  (blueprint-test--with-project
    (let ((comps (blueprint--components)))
      (should (hash-table-p comps))
      (should (= 0 (hash-table-count comps))))))

(ert-deftest blueprint-test-components/one-component ()
  "A single component is enumerated correctly."
  (blueprint-test--with-project
    (blueprint-test--write-component "api")
    (let ((comps (blueprint--components)))
      (should (= 1 (hash-table-count comps)))
      (should (gethash "api" comps))
      (should (file-directory-p (gethash "api" comps))))))

(ert-deftest blueprint-test-components/multiple ()
  "Multiple components are all enumerated."
  (blueprint-test--with-project
    (blueprint-test--write-component "api")
    (blueprint-test--write-component "auth")
    (blueprint-test--write-component "db")
    (let ((comps (blueprint--components)))
      (should (= 3 (hash-table-count comps)))
      (should (gethash "api" comps))
      (should (gethash "auth" comps))
      (should (gethash "db" comps)))))

;;; --- blueprint--component-file ---

(ert-deftest blueprint-test-component-file/exists ()
  "Returns the correct arc42.org path for an existing component."
  (blueprint-test--with-project
    (let ((written (blueprint-test--write-component "mycomp")))
      (let ((result (blueprint--component-file "mycomp")))
        (should (stringp result))
        (should (string-suffix-p "arc42.org" result))
        (should (file-exists-p result))))))

(ert-deftest blueprint-test-component-file/missing ()
  "Returns nil when the component does not exist."
  (blueprint-test--with-project
    (should (null (blueprint--component-file "nonexistent")))))

;;; --- blueprint--cached-metrics ---

(ert-deftest blueprint-test-cache/miss-then-hit ()
  "Cache starts empty; second call returns cached value without re-computing."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component "cache-test" "content")))
      (blueprint--invalidate-cache)
      (let ((call-count 0))
        (let ((fn (lambda (_f)
                    (cl-incf call-count)
                    '(1 2 3))))
          ;; First call: cache miss → fn is called
          (blueprint--cached-metrics file fn)
          (should (= 1 call-count))
          ;; Second call: cache hit → fn not called again
          (blueprint--cached-metrics file fn)
          (should (= 1 call-count)))))))

(ert-deftest blueprint-test-cache/invalidated-on-change ()
  "Cache is invalidated when a file's content changes."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component "cache-inv" "original")))
      (blueprint--invalidate-cache)
      (let ((call-count 0))
        (let ((fn (lambda (_f)
                    (cl-incf call-count)
                    call-count)))
          (blueprint--cached-metrics file fn)
          (should (= 1 call-count))
          ;; Modify the file
          (with-temp-file file (insert "modified content"))
          ;; Next call should re-compute
          (blueprint--cached-metrics file fn)
          (should (= 2 call-count)))))))

(ert-deftest blueprint-test-cache/invalidate-single ()
  "Invalidating a specific file does not affect other cache entries."
  (blueprint-test--with-project
    (let ((file-a (blueprint-test--write-component "comp-a" "content-a"))
          (file-b (blueprint-test--write-component "comp-b" "content-b")))
      (blueprint--invalidate-cache)
      (let ((count-a 0) (count-b 0))
        (blueprint--cached-metrics file-a (lambda (_) (cl-incf count-a) '(0 0 0)))
        (blueprint--cached-metrics file-b (lambda (_) (cl-incf count-b) '(0 0 0)))
        ;; Invalidate only file-a
        (blueprint--invalidate-cache file-a)
        (blueprint--cached-metrics file-a (lambda (_) (cl-incf count-a) '(0 0 0)))
        (blueprint--cached-metrics file-b (lambda (_) (cl-incf count-b) '(0 0 0)))
        (should (= 2 count-a))   ; recomputed
        (should (= 1 count-b)))))) ; still cached

(ert-deftest blueprint-test-cache/kind-keys-do-not-collide ()
  "Entries with a KIND are keyed apart from the plain FILE entry.
Invalidating FILE drops both."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component "comp-k" "content")))
      (blueprint--invalidate-cache)
      (should (equal '(1 2 3)
                     (blueprint--cached-metrics file (lambda (_) '(1 2 3)))))
      (should (equal 'other
                     (blueprint--cached-metrics file (lambda (_) 'other)
                                                'some-kind)))
      ;; Each key returns its own value from the cache.
      (should (equal '(1 2 3)
                     (blueprint--cached-metrics file (lambda (_) 'wrong))))
      (should (equal 'other
                     (blueprint--cached-metrics file (lambda (_) 'wrong)
                                                'some-kind)))
      (blueprint--invalidate-cache file)
      (should-not (gethash file blueprint--metrics-cache))
      (should-not (gethash (cons file 'some-kind) blueprint--metrics-cache)))))

;;; --- Component navigation ---

(ert-deftest blueprint-test-navigation/single-document-no-prompt ()
  "With only arc42.org the chooser returns it without asking."
  (blueprint-test--with-project
    (let ((arc42 (blueprint-test--write-component "solo")))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Should not prompt"))))
        (should (equal arc42 (blueprint--read-component-document "solo")))))))

(ert-deftest blueprint-test-navigation/chooser-offers-existing-documents ()
  "The chooser offers the existing documents, arc42.org preselected."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (let ((func (blueprint-test--write-document "svc" "functional.org" "x\n"))
          offered default)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest args)
                   (setq offered collection
                         default (nth 4 args))
                   "functional.org")))
        (should (equal func (blueprint--read-component-document "svc"))))
      (should (equal offered '("arc42.org" "functional.org")))
      (should (equal default "arc42.org")))))

(ert-deftest blueprint-test-navigation/visit-each-document ()
  "`blueprint-visit-component' opens each of the three documents."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component "svc"))
           (func (blueprint-test--write-document "svc" "functional.org" "f\n"))
           (infra (blueprint-test--write-document
                   "svc" "infrastructure.org" "i\n")))
      (dolist (pair (list (cons "arc42.org" arc42)
                          (cons "functional.org" func)
                          (cons "infrastructure.org" infra)))
        ;; Explicit document argument.
        (with-current-buffer (blueprint-visit-component "svc" (car pair))
          (should (equal (buffer-file-name) (cdr pair))))
        ;; Chosen interactively through the chooser.
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) (car pair))))
          (with-current-buffer (blueprint-visit-component "svc")
            (should (equal (buffer-file-name) (cdr pair)))))))))

(ert-deftest blueprint-test-navigation/visit-missing-document-errors ()
  "Asking for a document the component lacks is a user error."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (should-error (blueprint-visit-component "svc" "functional.org")
                  :type 'user-error)
    (should-error (blueprint-visit-component "ghost") :type 'user-error)))

(ert-deftest blueprint-test-navigation/components-list-keys ()
  "The components list has its own keymap: RET asks, a/f/i open directly.
Its bindings do not leak into `tabulated-list-mode-map'."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (let ((infra (blueprint-test--write-document
                  "svc" "infrastructure.org" "i\n")))
      (unwind-protect
          (progn
            (blueprint-list-components)
            (with-current-buffer "*Blueprint Components*"
              (should (eq major-mode 'blueprint-components-mode))
              (should (eq (key-binding (kbd "RET"))
                          #'blueprint-components-visit))
              (should (eq (key-binding (kbd "i"))
                          #'blueprint-components-visit-infrastructure))
              (should (equal (aref (cadr (assoc "svc" tabulated-list-entries)) 1)
                             "arc42.org infrastructure.org"))
              (goto-char (point-min))
              (while (and (not (equal (tabulated-list-get-id) "svc"))
                          (not (eobp)))
                (forward-line 1))
              (call-interactively #'blueprint-components-visit-infrastructure)
              (should (equal (buffer-file-name) infra))))
        (when (get-buffer "*Blueprint Components*")
          (kill-buffer "*Blueprint Components*")))
      (should-not (eq (lookup-key tabulated-list-mode-map (kbd "RET"))
                      #'blueprint-components-visit)))))

;;; --- blueprint-init ---

(ert-deftest blueprint-test-init/creates-directories ()
  "blueprint-init creates the expected directory structure."
  (let* ((tmpdir (make-temp-file "blueprint-init-test-" t))
         (default-directory (file-name-as-directory tmpdir)))
    (unwind-protect
        (progn
          (blueprint-init)
          (should (file-directory-p (expand-file-name ".blueprint" tmpdir)))
          (should (file-directory-p (expand-file-name ".blueprint/components" tmpdir)))
          (should (file-directory-p (expand-file-name ".blueprint/adr" tmpdir))))
      (delete-directory tmpdir t))))

(ert-deftest blueprint-test-init/idempotent ()
  "Calling blueprint-init twice does not error."
  (blueprint-test--with-project
    (should (progn (blueprint-init) t))))

;;; --- blueprint-add-component ---

(ert-deftest blueprint-test-add-component/creates-file ()
  "blueprint-add-component creates the arc42.org file."
  (blueprint-test--with-project
    ;; Save project dir BEFORE blueprint-add-component, which calls find-file
    ;; and changes the current buffer (and thus buffer-local default-directory).
    (let ((proj default-directory))
      (blueprint-add-component "newcomp")
      (should (file-exists-p
               (expand-file-name ".blueprint/components/newcomp/arc42.org"
                                 proj))))))

(ert-deftest blueprint-test-add-component/replaces-name-placeholder ()
  "The {{NAME}} placeholder in the template is replaced with the component name."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-add-component "myservice")
      (let ((content (blueprint-test--read-file
                      (expand-file-name
                       ".blueprint/components/myservice/arc42.org"
                       proj))))
        (should (string-match-p "myservice" content))
        (should-not (string-match-p "{{NAME}}" content))))))

(ert-deftest blueprint-test-add-component/duplicate-name-errors ()
  "Adding a component whose id already exists signals a user-error,
instead of silently overwriting the existing arc42.org back to the
blank template (`make-directory' with PARENTS=t does not error on an
already-existing directory, so this must be checked explicitly)."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-add-component "svc")
      (let ((file (expand-file-name ".blueprint/components/svc/arc42.org" proj)))
        ;; Simulate pre-existing work that a silent overwrite would lose.
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-max))
          (insert "\nDo not lose this.\n")
          (write-region (point-min) (point-max) file))
        (let ((before (blueprint-test--read-file file)))
          (should-error (blueprint-add-component "svc") :type 'user-error)
          (should (equal before (blueprint-test--read-file file))))))))

(ert-deftest blueprint-test-add-component/slugify-collision-errors ()
  "Two display names that slugify to the same id are treated as a
collision, not two distinct components."
  (blueprint-test--with-project
    (blueprint-add-component "Order Service")
    (should-error (blueprint-add-component "order-service") :type 'user-error)))

;;; --- blueprint-rename-component ---

(ert-deftest blueprint-test-rename-component/renames-directory ()
  "Renaming a component renames its directory."
  (blueprint-test--with-project
    (blueprint-test--write-component "old-name")
    (blueprint-rename-component "old-name" "new-name")
    (should-not (file-directory-p
                 (expand-file-name ".blueprint/components/old-name"
                                   default-directory)))
    (should (file-directory-p
             (expand-file-name ".blueprint/components/new-name"
                               default-directory)))))

(ert-deftest blueprint-test-rename-component/collision-with-existing-fails-safely ()
  "Renaming onto an existing component's name fails instead of
silently overwriting it (`rename-file' signals `file-already-exists'
without an explicit OK-IF-ALREADY-EXISTS argument, which
blueprint-rename-component does not pass)."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "alpha")
      (blueprint-test--write-component "beta")
      (should-error (blueprint-rename-component "alpha" "beta"))
      ;; Both original components must survive the failed rename.
      (should (file-directory-p
               (expand-file-name ".blueprint/components/alpha" proj)))
      (should (file-directory-p
               (expand-file-name ".blueprint/components/beta" proj))))))

(ert-deftest blueprint-test-rename-component/hyphenated-dep-untouched ()
  "Renaming \"auth\" does not rewrite a dependency on \"auth-db\".
Regression: the old \\b-delimited regex treated the hyphen as a word
boundary and produced \"identity-db\", a component that does not exist."
  (blueprint-test--with-project
    (blueprint-test--write-component "auth")
    (blueprint-test--write-component "auth-db")
    (let ((file (blueprint-test--write-component
                 "api" "#+TITLE: api\n#+BLUEPRINT_DEPENDS: auth-db auth\n\n* Introduction\n")))
      (blueprint-rename-component "auth" "identity")
      (should (equal "auth-db identity"
                     (blueprint--org-keyword file "BLUEPRINT_DEPENDS"))))))

(ert-deftest blueprint-test-rename-component/src-block-example-untouched ()
  "A DEPENDS line inside a src block example is not rewritten."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (let ((file (blueprint-test--write-component
                 "beta"
                 (concat "#+TITLE: beta\n#+BLUEPRINT_DEPENDS: alpha\n\n"
                         "* Guida :noexport:\n#+BEGIN_SRC org\n"
                         "#+BLUEPRINT_DEPENDS: alpha other\n#+END_SRC\n"))))
      (blueprint-rename-component "alpha" "gamma")
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "^#\\+BLUEPRINT_DEPENDS: gamma$" content))
        (should (string-match-p "^#\\+BLUEPRINT_DEPENDS: alpha other$" content))))))

(ert-deftest blueprint-test-rename-component/updates-depends ()
  "Renaming updates BLUEPRINT_DEPENDS references in other components."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component
     "beta"
     "#+TITLE: beta\n#+BLUEPRINT_DEPENDS: alpha\n\n* Introduction\n")
    (blueprint-rename-component "alpha" "gamma")
    (let ((content (blueprint-test--read-file
                    (expand-file-name
                     ".blueprint/components/beta/arc42.org"
                     default-directory))))
      (should (string-match-p "gamma" content))
      (should-not (string-match-p "\\balpha\\b" content)))))

;;; --- blueprint-delete-component ---

(ert-deftest blueprint-test-delete-component/removes-directory ()
  "Deleting a component removes its directory."
  (blueprint-test--with-project
    (blueprint-test--write-component "todelete")
    ;; Bypass confirmation prompt
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (blueprint-delete-component "todelete"))
    (should-not (file-directory-p
                 (expand-file-name ".blueprint/components/todelete"
                                   default-directory)))))

(defun blueprint-test--write-synced-master (&optional manual page-breaks)
  "Write a master.org with the three sync-marker sections.
MANUAL, when non-nil, is text written outside the markers (it must
survive the sync).  PAGE-BREAKS non-nil adds the
#+BLUEPRINT_PAGE_BREAK: keyword.  Written before `blueprint-sync' so
the file is never changed on disk behind an open buffer."
  (blueprint-test--write-file
   "master.org"
   (concat "#+TITLE: Doc\n\n* Parte 0\n\n"
           (or manual "Introduzione del documento.")
           "\n\n"
           (when page-breaks "#+BLUEPRINT_PAGE_BREAK: components\n\n")
           "# @@blueprint-sync-start@@\n"
           "# @@blueprint-sync-end@@\n\n"
           "# @@blueprint-sync-functional-start@@\n"
           "# @@blueprint-sync-functional-end@@\n\n"
           "# @@blueprint-sync-infra-start@@\n"
           "# @@blueprint-sync-infra-end@@\n")))

(ert-deftest blueprint-test-delete-component/removes-synced-includes ()
  "Deleting a component removes its includes and headline from master.org.
Content outside the sync markers is untouched."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component "beta")
    (require 'blueprint-sync)
    (blueprint-test--write-synced-master "Testo manuale fuori dai marker.")
    (blueprint-sync)
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (blueprint-delete-component "alpha"))
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      (should-not (string-match-p
                   "#\\+INCLUDE: \".blueprint/components/alpha/arc42.org\"" content))
      (should-not (string-match-p "^\\*\\* alpha$" content))
      (should (string-match-p
               "#\\+INCLUDE: \".blueprint/components/beta/arc42.org\"" content))
      (should (string-match-p "^\\*\\* beta$" content))
      (should (string-match-p
               (regexp-quote "Testo manuale fuori dai marker.") content))
      ;; The markers themselves survive.
      (should (string-match-p (regexp-quote blueprint-sync-start-marker) content))
      (should (string-match-p (regexp-quote blueprint-sync-end-marker) content)))))

(ert-deftest blueprint-test-delete-component/page-break-removed-with-headline ()
  "Deleting a component removes the page-break lines before its headline."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component "beta")
    (blueprint-test--write-component "charlie")
    (require 'blueprint-sync)
    (blueprint-test--write-synced-master nil t)
    (blueprint-sync)
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (blueprint-delete-component "beta"))
    (let ((master (expand-file-name "master.org" default-directory)))
      (with-temp-buffer
        (insert (blueprint-test--read-file master))
        (goto-char (point-min))
        ;; Only the break before charlie remains (beta had one, alpha none).
        (should (= 1 (count-matches "PageBreak"))))
      (should-not (string-match-p "^\\*\\* beta$"
                                  (blueprint-test--read-file master))))))

(ert-deftest blueprint-test-delete-component/dependents-confirmed-and-reported ()
  "Deleting a component asked about dependents and leaves their DEPENDS alone."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-component
     "beta"
     (concat "#+TITLE: beta\n#+BLUEPRINT_DEPENDS: alpha\n\n"
             "* Introduction\n\n* Open Questions\n"))
    (require 'blueprint-sync)
    (blueprint-sync)
    (should (equal (blueprint--component-dependents "alpha") '("beta")))
    (let ((asked '()))
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (prompt) (push prompt asked) t)))
        (blueprint-delete-component "alpha"))
      (should (= 1 (length asked)))
      (should (string-match-p "beta" (car asked)))
      (should (string-match-p "dangle" (car asked))))
    (should-not (file-directory-p
                 (expand-file-name ".blueprint/components/alpha"
                                   default-directory)))
    (let ((content (blueprint-test--read-file
                    (expand-file-name ".blueprint/components/beta/arc42.org"
                                      default-directory))))
      (should (string-match-p "#\\+BLUEPRINT_DEPENDS: alpha" content)))
    (should-not (string-match-p
                 "#\\+INCLUDE: \".blueprint/components/alpha/arc42.org\""
                 (blueprint-test--read-file
                  (expand-file-name "master.org" default-directory))))))

(ert-deftest blueprint-test-delete-component/legacy-master-without-headlines ()
  "A master.org in the pre-9.14 format (bare includes) is cleaned without errors."
  (blueprint-test--with-project
    (blueprint-test--write-component "alpha")
    (blueprint-test--write-file
     "master.org"
     (concat "#+TITLE: Doc\n\n* Parte 0\n\nIntroduzione.\n\n"
             "# @@blueprint-sync-start@@\n"
             "#+INCLUDE: \".blueprint/components/alpha/arc42.org\" :minlevel 2\n"
             "# @@blueprint-sync-end@@\n\n"
             "# @@blueprint-sync-functional-start@@\n"
             "# @@blueprint-sync-functional-end@@\n\n"
             "# @@blueprint-sync-infra-start@@\n"
             "# @@blueprint-sync-infra-end@@\n"))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (blueprint-delete-component "alpha"))
    (let ((content (blueprint-test--read-file
                    (expand-file-name "master.org" default-directory))))
      (should-not (string-match-p "#\\+INCLUDE:" content))
      (should (string-match-p (regexp-quote blueprint-sync-start-marker) content))
      (should (string-match-p "^\\* Parte 0$" content)))))

;;; --- blueprint--resolve-template ---

(ert-deftest blueprint-test-resolve-template/system-fallback ()
  "System templates are resolved when no project or user override exists."
  (blueprint-test--with-project
    ;; blueprint-template-dir points to the package's templates/ directory
    (should (stringp (blueprint--resolve-template "component.org")))
    (should (file-exists-p (blueprint--resolve-template "component.org")))))

(ert-deftest blueprint-test-resolve-template/project-override ()
  "Project-local template takes priority over system template."
  (blueprint-test--with-project
    (let ((proj-tmpl-dir (expand-file-name ".blueprint/templates" default-directory)))
      (make-directory proj-tmpl-dir t)
      (with-temp-file (expand-file-name "component.org" proj-tmpl-dir)
        (insert "PROJECT-LOCAL-TEMPLATE"))
      (let ((resolved (blueprint--resolve-template "component.org")))
        (should (string-match-p ".blueprint/templates" resolved))
        (should (string= "PROJECT-LOCAL-TEMPLATE"
                         (blueprint-test--read-file resolved)))))))

;;; --- Component templates (standard vs enterprise, 9.5) ---

(ert-deftest blueprint-test-add-component/default-template-unchanged ()
  "Without a template argument the arc42.org comes from component.org,
as every pre-9.5 call and script expects."
  (blueprint-test--with-project
    (cl-letf (((symbol-function 'find-file) #'ignore))
      (blueprint-add-component "standard"))
    (let ((content (blueprint-test--read-file
                    (expand-file-name ".blueprint/components/standard/arc42.org"
                                      default-directory))))
      (should (string-match-p "^\\* Introduction$" content))
      (should-not (string-match-p "Contesto enterprise" content)))))

(ert-deftest blueprint-test-add-component/enterprise-template ()
  "With the enterprise template the arc42.org carries the three extra
sections (contesto enterprise, stakeholder, compliance) on top of the
standard arc42 ones the lint expects."
  (blueprint-test--with-project
    (cl-letf (((symbol-function 'find-file) #'ignore))
      (blueprint-add-component "servizio-critico" "arc42-enterprise.org"))
    (let ((content (blueprint-test--read-file
                    (expand-file-name ".blueprint/components/servizio-critico/arc42.org"
                                      default-directory))))
      (should (string-match-p "^\\* Contesto enterprise$" content))
      (should (string-match-p "^\\* Stakeholder e punti di contatto$" content))
      (should (string-match-p "^\\* Conformità e compliance$" content))
      ;; The standard arc42 headings are still there, so the lint sees
      ;; an enterprise component like any other.
      (should (string-match-p "^\\* Introduction$" content))
      (should (string-match-p "^\\* Building Blocks$" content))
      (should (string-match-p "<<servizio-critico-stakeholders>>" content))
      (should-not (string-match-p "{{" content)))))

(ert-deftest blueprint-test-add-component/enterprise-template-listed ()
  "`arc42-enterprise.org' is among the candidates
`blueprint-add-component' can resolve, and the three-tier lookup
applies: a project override wins over the system template."
  (blueprint-test--with-project
    (should (member "arc42-enterprise.org" blueprint--component-templates))
    (should (blueprint--resolve-template "arc42-enterprise.org"))
    (let ((proj-tmpl-dir (expand-file-name ".blueprint/templates" default-directory)))
      (make-directory proj-tmpl-dir t)
      (with-temp-file (expand-file-name "arc42-enterprise.org" proj-tmpl-dir)
        (insert "PROJECT-LOCAL-ENTERPRISE"))
      (should (string= "PROJECT-LOCAL-ENTERPRISE"
                       (blueprint--template "arc42-enterprise.org"))))))

;;; --- Configurable data directory (`blueprint-directory-name') ---

(ert-deftest blueprint-test-data-dir/name-validation ()
  "Only non-empty relative paths without . or .. segments are accepted."
  (dolist (ok '(".blueprint" "blueprint" "content/blueprint" "docs/bp/"))
    (should (blueprint--valid-directory-name-p ok)))
  (dolist (bad '("" "/abs/blueprint" "../outside" "a/../b" "." "a//b" nil 42))
    (should-not (blueprint--valid-directory-name-p bad))))

(ert-deftest blueprint-test-data-dir/invalid-name-errors ()
  "An invalid `blueprint-directory-name' signals a user-error, not a crash."
  (let ((blueprint-directory-name "../escape"))
    (should-error (blueprint--directory-name) :type 'user-error)))

(ert-deftest blueprint-test-data-dir/nested-custom-name ()
  "A nested custom name is used for root detection and components."
  (let ((blueprint-directory-name "content/blueprint"))
    (blueprint-test--with-project
      (let ((proj default-directory))
        (should (file-equal-p proj (blueprint--root)))
        (should (string= (expand-file-name "content/blueprint" proj)
                         (blueprint--data-dir)))
        (should-not (file-exists-p (expand-file-name ".blueprint" proj)))
        (blueprint-add-component "Order Service")
        (should (file-exists-p
                 (expand-file-name
                  "content/blueprint/components/order-service/arc42.org" proj)))
        (should (gethash "order-service" (blueprint--components)))))))

(ert-deftest blueprint-test-data-dir/root-from-inside-nested-dir ()
  "The root is found from a directory inside a nested data directory."
  (let ((blueprint-directory-name "content/blueprint"))
    (blueprint-test--with-project
      (let ((proj default-directory))
        (blueprint-test--write-component "svc")
        (let ((default-directory
               (expand-file-name "content/blueprint/components/svc/" proj)))
          (should (file-equal-p proj (blueprint--root))))))))

(ert-deftest blueprint-test-data-dir/legacy-fallback ()
  "A project still on .blueprint/ works under a different configured name."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (let ((blueprint-directory-name "blueprint")
            (blueprint--warned-roots (make-hash-table :test 'equal))
            (warnings 0))
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _) (cl-incf warnings))))
          (should (file-equal-p proj (blueprint--root)))
          (should (string= (expand-file-name ".blueprint" proj)
                           (blueprint--data-dir)))
          (should (gethash "svc" (blueprint--components)))
          ;; Warned once per root, however many commands call it.
          (blueprint--root)
          (blueprint--root)
          (should (= 1 warnings)))))))

(ert-deftest blueprint-test-data-dir/configured-wins-over-legacy ()
  "With both directories present the configured one is used, with a warning."
  (blueprint-test--with-project
    (let ((proj default-directory)
          (blueprint-directory-name "blueprint")
          (blueprint--warned-roots (make-hash-table :test 'equal))
          (msg nil))
      (make-directory (expand-file-name "blueprint/components" proj) t)
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type text &rest _) (setq msg text))))
        (should (string= (expand-file-name "blueprint" proj)
                         (blueprint--data-dir)))
        (blueprint--root)
        (should (string-match-p "both" msg))))))

(ert-deftest blueprint-test-data-dir/init-reuses-legacy ()
  "blueprint-init in a legacy project does not create a second, empty data dir."
  (blueprint-test--with-project
    (let ((proj default-directory)
          (blueprint-directory-name "blueprint")
          (blueprint--warned-roots (make-hash-table :test 'equal)))
      (cl-letf (((symbol-function 'display-warning) #'ignore))
        (blueprint-init "P" "A"))
      (should-not (file-exists-p (expand-file-name "blueprint" proj)))
      (should (file-directory-p (expand-file-name ".blueprint/templates" proj))))))

(ert-deftest blueprint-test-data-dir/init-creates-custom ()
  "blueprint-init in a fresh directory creates the configured data dir."
  (let* ((tmpdir (make-temp-file "blueprint-test-" t))
         (default-directory (file-name-as-directory tmpdir))
         (blueprint-directory-name "content/blueprint"))
    (unwind-protect
        (progn
          (blueprint-init "P" "A")
          (should (file-directory-p
                   (expand-file-name "content/blueprint/components" tmpdir)))
          (should-not (file-exists-p (expand-file-name ".blueprint" tmpdir))))
      (delete-directory tmpdir t))))

;;; --- Document files: master.org and its includes (PLAN 9.31) ---

(ert-deftest blueprint-test-document/nested-includes-relative-to-includer ()
  "Includes are followed recursively, each resolved against its includer.
nfr/all.org includes \"risks.org\", which is nfr/risks.org, not the
risks.org at the root."
  (blueprint-test--with-project
    (let* ((master (blueprint-test--write-master "glossary.org" "nfr/all.org"))
           (glossary (blueprint-test--write-file "glossary.org" "* G\n\nTerm.\n"))
           (all (blueprint-test--write-file
                 "nfr/all.org" "* NFR\n\n#+INCLUDE: \"risks.org\" :minlevel 3\n"))
           (risks (blueprint-test--write-file "nfr/risks.org" "* R\n\nRisk.\n")))
      (blueprint-test--write-file "risks.org" "* Wrong\n")
      (should (equal (blueprint--document-files)
                     (list master glossary all risks))))))

(ert-deftest blueprint-test-document/missing-files-reported ()
  "A missing included file is left out of the files and reported."
  (blueprint-test--with-project
    (let* ((master (blueprint-test--write-master "glossary.org" "nfr/ghost.org"))
           (glossary (blueprint-test--write-file "glossary.org" "* G\n")))
      (should (equal (blueprint--document-files) (list master glossary)))
      (should (equal (plist-get (blueprint--document-walk) :missing)
                     (list (cons (expand-file-name "nfr/ghost.org") master)))))))

(ert-deftest blueprint-test-document/cycle-terminates ()
  "Files that include each other are listed once."
  (blueprint-test--with-project
    (let ((master (blueprint-test--write-master "a.org"))
          (a (blueprint-test--write-file "a.org" "#+INCLUDE: \"b.org\"\n"))
          (b (blueprint-test--write-file
              "b.org" "#+INCLUDE: \"a.org\"\n#+INCLUDE: \"master.org\"\n")))
      (should (equal (blueprint--document-files) (list master a b))))))

(ert-deftest blueprint-test-document/skips-non-exported-includes ()
  "Includes in :noexport: subtrees, comments and blocks are not followed.
An include as a src/example block is not live text either."
  (blueprint-test--with-project
    (let ((master (blueprint-test--write-file
                   "master.org"
                   (concat "#+TITLE: Doc\n\n"
                           "# #+INCLUDE: \"commented.org\"\n"
                           "* Guide :noexport:\n#+INCLUDE: \"hidden.org\"\n"
                           "* Body\n"
                           "#+begin_example\n#+INCLUDE: \"example.org\"\n#+end_example\n"
                           "#+INCLUDE: \"code.org\" src org\n"
                           "#+INCLUDE: \"shown.org\" :minlevel 2\n"))))
      (dolist (f '("commented.org" "hidden.org" "example.org" "code.org"))
        (blueprint-test--write-file f "QUESTION\n"))
      (let ((shown (blueprint-test--write-file "shown.org" "* S\n")))
        (should (equal (blueprint--document-files) (list master shown)))))))

(ert-deftest blueprint-test-document/parse-include-value ()
  "File, search suffix, block type and partial options are recognized."
  (let ((dir "/p/"))
    (should (equal (blueprint--parse-include-value "\"a.org\" :minlevel 3" dir)
                   '(:path "/p/a.org" :block nil :partial nil)))
    (should (equal (blueprint--parse-include-value "b.org::*Head" dir)
                   '(:path "/p/b.org" :block nil :partial t)))
    (should (equal (blueprint--parse-include-value "\"c.org\" :lines \"1-5\"" dir)
                   '(:path "/p/c.org" :block nil :partial t)))
    (should (plist-get (blueprint--parse-include-value "\"d.el\" src emacs-lisp" dir)
                       :block))
    (should (equal (plist-get (blueprint--parse-include-value "\"sub/e.org\"" "/p/q/")
                              :path)
                   "/p/q/sub/e.org"))
    (should-not (blueprint--parse-include-value "" dir))))

(ert-deftest blueprint-test-document/fallback-without-master ()
  "Without master.org the document is every component document."
  (blueprint-test--with-project
    (let* ((a (blueprint-test--write-component "a"))
           (af (blueprint-test--write-document "a" "functional.org" "f\n"))
           (b (blueprint-test--write-component "b")))
      (blueprint-test--write-file "notes.org" "QUESTION\n")
      (should (equal (blueprint--document-files) (list a af b))))))

(ert-deftest blueprint-test-document/units-components-then-parts ()
  "Each document file belongs to one row: components, then other files."
  (blueprint-test--with-project
    (let* ((arc (blueprint-test--write-component "svc"))
           (_fun (blueprint-test--write-document "svc" "functional.org" "f\n"))
           (_off (blueprint-test--write-component "off"))
           (master (blueprint-test--write-master
                    ".blueprint/components/svc/arc42.org" "nfr/risks.org"))
           (risks (blueprint-test--write-file "nfr/risks.org" "* R\n")))
      (should (equal (blueprint--document-units)
                     (list (list :id "off" :kind 'component :files nil :included nil)
                           (list :id "svc" :kind 'component :files (list arc)
                                 :included t)
                           (list :id "master.org" :kind 'part :files (list master)
                                 :included t)
                           (list :id "nfr/risks.org" :kind 'part :files (list risks)
                                 :included t)))))))

(ert-deftest blueprint-test-document/visit-part ()
  "`blueprint-visit-component' opens a part of the document by its path."
  (blueprint-test--with-project
    (blueprint-test--write-master "nfr/risks.org")
    (let ((risks (blueprint-test--write-file "nfr/risks.org" "* R\n")))
      (with-current-buffer (blueprint-visit-component "nfr/risks.org")
        (should (equal (buffer-file-name) risks))))
    (should-error (blueprint-visit-component "notes.org") :type 'user-error)))

(ert-deftest blueprint-test-document/includes-cached-and-invalidated ()
  "The include list of a file is cached under the kind `includes'."
  (blueprint-test--with-project
    (let ((master (blueprint-test--write-master "a.org")))
      (blueprint-test--write-file "a.org" "* A\n")
      (blueprint--document-files)
      (should (gethash (cons master 'includes) blueprint--metrics-cache))
      (blueprint-test--write-master "a.org" "b.org")
      (let ((b (blueprint-test--write-file "b.org" "* B\n")))
        (should (member b (blueprint--document-files)))))))

(provide 'blueprint-test-core)
;;; blueprint-test-core.el ends here
