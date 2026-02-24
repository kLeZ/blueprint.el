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

(provide 'blueprint-test-core)
;;; blueprint-test-core.el ends here
