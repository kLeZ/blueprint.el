;;; blueprint-test-migrate.el --- Tests for blueprint-migrate.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for template diff/migration: `blueprint-template-migrate' copies
;; missing system templates into a project non-destructively, and
;; `blueprint-template-diff' compares project templates against system
;; defaults.

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

(provide 'blueprint-test-migrate)
;;; blueprint-test-migrate.el ends here
