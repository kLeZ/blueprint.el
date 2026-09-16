;;; blueprint-test-watch.el --- Tests for blueprint-watch.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the auto-tangle and watch-mode minor modes: hook
;; install/remove on toggle, and project-membership detection.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-watch)

(defmacro blueprint-test--with-mode-off (mode &rest body)
  "Run BODY, then ensure global minor mode MODE ends up disabled.
Global minor modes mutate `after-save-hook' for the whole Emacs
session, so a test that enables one must always disable it again,
even if BODY errors, to avoid leaking the hook into unrelated tests."
  (declare (indent 1) (debug t))
  `(unwind-protect
       (progn ,@body)
     (when ,mode (funcall ,mode -1))))

(ert-deftest blueprint-test-watch/auto-tangle-mode-installs-hook ()
  "Enabling blueprint-auto-tangle-mode adds its hook to after-save-hook."
  (blueprint-test--with-mode-off 'blueprint-auto-tangle-mode
    (blueprint-auto-tangle-mode 1)
    (should (memq #'blueprint--auto-tangle-hook after-save-hook))))

(ert-deftest blueprint-test-watch/auto-tangle-mode-removes-hook ()
  "Disabling blueprint-auto-tangle-mode removes its hook from after-save-hook."
  (blueprint-test--with-mode-off 'blueprint-auto-tangle-mode
    (blueprint-auto-tangle-mode 1)
    (blueprint-auto-tangle-mode -1)
    (should-not (memq #'blueprint--auto-tangle-hook after-save-hook))))

(ert-deftest blueprint-test-watch/watch-mode-installs-hook ()
  "Enabling blueprint-watch-mode adds its hook to after-save-hook."
  (blueprint-test--with-mode-off 'blueprint-watch-mode
    (blueprint-watch-mode 1)
    (should (memq #'blueprint--watch-hook after-save-hook))))

(ert-deftest blueprint-test-watch/watch-mode-removes-hook ()
  "Disabling blueprint-watch-mode removes its hook from after-save-hook."
  (blueprint-test--with-mode-off 'blueprint-watch-mode
    (blueprint-watch-mode 1)
    (blueprint-watch-mode -1)
    (should-not (memq #'blueprint--watch-hook after-save-hook))))

(ert-deftest blueprint-test-watch/in-project-p-true-inside-blueprint-dir ()
  "blueprint--in-project-p is non-nil for a file under .blueprint/."
  (blueprint-test--with-project
    (let* ((file (blueprint-test--write-component "svc")))
      (with-current-buffer (find-file-noselect file)
        (should (blueprint--in-project-p))))))

(ert-deftest blueprint-test-watch/in-project-p-false-outside-project ()
  "blueprint--in-project-p is nil for a file outside any Blueprint project."
  (let* ((tmpdir (make-temp-file "blueprint-test-noproj-" t))
         (file (expand-file-name "plain.org" tmpdir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Not a project\n"))
          (with-current-buffer (find-file-noselect file)
            (should-not (blueprint--in-project-p))))
      (dolist (buf (buffer-list))
        (when (and (buffer-file-name buf)
                   (string-prefix-p tmpdir (buffer-file-name buf)))
          (kill-buffer buf)))
      (delete-directory tmpdir t))))

(ert-deftest blueprint-test-watch/watch-hook-invalidates-cache ()
  "blueprint--watch-hook invalidates the metrics cache for the saved file."
  (blueprint-test--with-project
    (let* ((file (blueprint-test--write-component "svc"))
           (blueprint-watch-auto-sync nil)
           (blueprint-watch-auto-c4 nil))
      (with-current-buffer (find-file-noselect file)
        ;; Populate the cache, then verify the hook clears this file's entry.
        (blueprint--cached-metrics file #'blueprint--component-metrics)
        (should (gethash file blueprint--metrics-cache))
        (blueprint--watch-hook)
        (should-not (gethash file blueprint--metrics-cache))))))

(provide 'blueprint-test-watch)
;;; blueprint-test-watch.el ends here
