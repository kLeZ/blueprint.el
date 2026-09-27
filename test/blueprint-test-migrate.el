;;; blueprint-test-migrate.el --- Tests for blueprint-migrate.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for template diff/migration: `blueprint-template-migrate' copies
;; missing system templates into a project non-destructively, and
;; `blueprint-template-diff' compares project templates against system
;; defaults.  `blueprint-migrate-directory' renames the data directory
;; and rewrites the Org paths pointing into it.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-migrate)

(ert-deftest blueprint-test-migrate/copies-missing-templates ()
  "blueprint-template-migrate copies every system template into the project."
  (blueprint-test--with-project
    (blueprint-template-migrate)
    (let ((dst (blueprint--project-template-dir)))
      (should (file-directory-p dst))
      (dolist (f (directory-files blueprint-template-dir nil "^[^.]"))
        (should (file-exists-p (expand-file-name f dst)))))))

(ert-deftest blueprint-test-migrate/non-destructive ()
  "blueprint-template-migrate never overwrites an existing project template."
  (blueprint-test--with-project
    (let* ((dst (blueprint--project-template-dir))
           (target (expand-file-name "component.org" dst)))
      (make-directory dst t)
      (with-temp-file target
        (insert "customized project template, must survive migration\n"))
      (blueprint-template-migrate)
      (should (string-match-p
               "customized project template"
               (blueprint-test--read-file target))))))

(ert-deftest blueprint-test-migrate/diff-errors-without-project-templates ()
  "blueprint-template-diff signals a user-error with no project templates dir."
  (blueprint-test--with-project
    (should-error (blueprint-template-diff) :type 'user-error)))

(ert-deftest blueprint-test-migrate/diff-runs-after-migration ()
  "blueprint-template-diff does not error once project templates exist."
  (blueprint-test--with-project
    (blueprint-template-migrate)
    (let ((buffers-before (buffer-list)))
      (unwind-protect
          (progn
            (blueprint-template-diff)
            ;; Reaching this point means no error was signaled.
            (should t))
        ;; `diff' runs as an async subprocess via `compilation-start';
        ;; killing its buffer would otherwise prompt
        ;; "process still running, kill it?", which reads from stdin
        ;; and aborts the test in batch mode.
        (let ((kill-buffer-query-functions nil))
          (dolist (buf (buffer-list))
            (unless (memq buf buffers-before)
              (kill-buffer buf))))))))

;;; --- blueprint-migrate-directory ---

(defun blueprint-test-migrate--write (path content)
  "Write CONTENT to PATH (relative to `default-directory'), creating dirs."
  (let ((file (expand-file-name path default-directory)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert content))
    file))

(defmacro blueprint-test-migrate--quietly (&rest body)
  "Run BODY with a fresh warning registry and warnings silenced."
  (declare (indent 0) (debug t))
  `(let ((blueprint--warned-roots (make-hash-table :test 'equal)))
     (cl-letf (((symbol-function 'display-warning) #'ignore))
       ,@body)))

(ert-deftest blueprint-test-migrate-dir/renames-and-rewrites ()
  "Migration moves the data dir and rewrites includes and links both ways."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-component "db")
      (blueprint-test-migrate--write
       "master.org"
       (concat "#+TITLE: M\n"
               "#+INCLUDE: \".blueprint/components/svc/arc42.org\" :minlevel 3\n"
               "#+INCLUDE: \"glossary.org\"\n"
               "See [[file:.blueprint/components/db/arc42.org::*Risks][db risks]].\n"
               "Prose mentioning .blueprint/components stays as is.\n"))
      (blueprint-test-migrate--write "glossary.org" "#+TITLE: G\n")
      (blueprint-test-migrate--write
       "enterprise/context.org"
       "Link: [[file:../.blueprint/components/svc/arc42.org]]\n")
      (blueprint-test-migrate--write
       ".blueprint/components/svc/functional.org"
       (concat "Out: [[file:../../../glossary.org]]\n"
               "Sibling: [[file:../db/arc42.org]]\n"))
      (let ((blueprint-directory-name "content/blueprint"))
        (blueprint-test-migrate--quietly
          (blueprint-migrate-directory nil t))
        (should-not (file-exists-p (expand-file-name ".blueprint" proj)))
        (should (file-exists-p
                 (expand-file-name "content/blueprint/components/svc/arc42.org"
                                   proj)))
        (let ((master (blueprint-test--read-file
                       (expand-file-name "master.org" proj))))
          (should (string-match-p
                   (regexp-quote "#+INCLUDE: \"content/blueprint/components/svc/arc42.org\" :minlevel 3")
                   master))
          (should (string-match-p (regexp-quote "#+INCLUDE: \"glossary.org\"")
                                  master))
          (should (string-match-p
                   (regexp-quote "[[file:content/blueprint/components/db/arc42.org::*Risks][db risks]]")
                   master))
          ;; Plain text is reported, not rewritten.
          (should (string-match-p (regexp-quote "Prose mentioning .blueprint/")
                                  master)))
        (should (string-match-p
                 (regexp-quote "[[file:../content/blueprint/components/svc/arc42.org]]")
                 (blueprint-test--read-file
                  (expand-file-name "enterprise/context.org" proj))))
        ;; The moved tree is one level deeper: outward links gain a "../",
        ;; links inside the tree are untouched.
        (let ((func (blueprint-test--read-file
                     (expand-file-name
                      "content/blueprint/components/svc/functional.org" proj))))
          (should (string-match-p (regexp-quote "[[file:../../../../glossary.org]]")
                                  func))
          (should (string-match-p (regexp-quote "[[file:../db/arc42.org]]") func)))
        (should (gethash "svc" (blueprint--components)))))))

(ert-deftest blueprint-test-migrate-dir/plan-reports-leftovers ()
  "The plan lists plain-text mentions of the old directory."
  (blueprint-test--with-project
    (let* ((proj (expand-file-name default-directory))
           (from (expand-file-name ".blueprint" proj))
           (to (expand-file-name "blueprint" proj)))
      (blueprint-test-migrate--write
       "notes.org"
       (concat "[[file:.blueprint/x.org]]\n"
               "#+begin_src plantuml :file .blueprint/out.svg\n#+end_src\n"))
      (let* ((plan (blueprint--migrate-directory-plan proj from to))
             (leftovers (plist-get plan :leftovers)))
        (should (= 1 (length (plist-get plan :edits))))
        (should (= 1 (length leftovers)))
        (should (= 2 (nth 1 (car leftovers))))))))

(ert-deftest blueprint-test-migrate-dir/refuses-existing-target ()
  "Migration refuses to overwrite or merge into an existing directory."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (make-directory (expand-file-name "blueprint" proj))
      (blueprint-test-migrate--quietly
        (should-error (blueprint-migrate-directory "blueprint" t)
                      :type 'user-error))
      (should (file-directory-p (expand-file-name ".blueprint/components" proj))))))

(ert-deftest blueprint-test-migrate-dir/refuses-same-and-nested ()
  "Migration refuses a no-op, a nested target and an invalid name."
  (blueprint-test--with-project
    (blueprint-test-migrate--quietly
      (should-error (blueprint-migrate-directory ".blueprint" t) :type 'user-error)
      (should-error (blueprint-migrate-directory ".blueprint/inner" t)
                    :type 'user-error)
      (should-error (blueprint-migrate-directory "../outside" t)
                    :type 'user-error))))

(ert-deftest blueprint-test-migrate-dir/refuses-modified-buffer ()
  "Migration refuses while a buffer under the data dir has unsaved changes."
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (file (blueprint-test--write-component "svc")))
      (with-current-buffer (find-file-noselect file)
        (insert "unsaved")
        (let ((default-directory proj))
          (blueprint-test-migrate--quietly
            (should-error (blueprint-migrate-directory "blueprint" t)
                          :type 'user-error)))
        (set-buffer-modified-p nil))
      (should (file-exists-p file)))))

(ert-deftest blueprint-test-migrate-dir/repoints-visiting-buffers ()
  "Buffers visiting files under the old directory follow the rename."
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (file (blueprint-test--write-component "svc"))
           (buf (find-file-noselect file)))
      (let ((blueprint-directory-name "blueprint"))
        (blueprint-test-migrate--quietly
          (blueprint-migrate-directory nil t)))
      (should (string= (expand-file-name "blueprint/components/svc/arc42.org" proj)
                       (buffer-file-name buf)))
      (should (string= (expand-file-name "blueprint/components/svc/" proj)
                       (buffer-local-value 'default-directory buf))))))

(ert-deftest blueprint-test-migrate-dir/uses-git-mv ()
  "In a git work tree the rename is staged with git mv."
  (skip-unless (executable-find "git"))
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (let ((process-environment
             (append '("GIT_AUTHOR_NAME=t" "GIT_AUTHOR_EMAIL=t@t"
                       "GIT_COMMITTER_NAME=t" "GIT_COMMITTER_EMAIL=t@t")
                     process-environment)))
        (dolist (args '(("init" "-q") ("add" ".") ("commit" "-q" "-m" "init")))
          (should (eq 0 (apply #'process-file "git" nil nil nil args))))
        ;; An untracked file must move along with the tracked ones.
        (blueprint-test-migrate--write ".blueprint/untracked.org" "x\n")
        (let ((blueprint-directory-name "blueprint"))
          (blueprint-test-migrate--quietly
            (blueprint-migrate-directory nil t)))
        (should (file-exists-p (expand-file-name "blueprint/untracked.org" proj)))
        (should-not (file-exists-p (expand-file-name ".blueprint" proj)))
        (should (string-match-p
                 "^R[0-9]*\t\\.blueprint/components/svc/arc42\\.org\tblueprint/components/svc/arc42\\.org"
                 (with-temp-buffer
                   (process-file "git" nil t nil "diff" "--cached"
                                 "--name-status" "-M")
                   (buffer-string))))))))

(provide 'blueprint-test-migrate)
;;; blueprint-test-migrate.el ends here
