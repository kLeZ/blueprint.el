;;; blueprint-test-preview.el --- Tests for blueprint-preview.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the live preview: mode install/remove, the debounced save
;; hook (with a stubbed generator), and the preview buffer update.
;; The refactor of `blueprint-dashboard-svg' is covered by the existing
;; dashboard tests.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-preview)

(ert-deftest blueprint-test-preview/mode-installs-and-removes-hook ()
  "Enabling the mode adds the after-save hook, disabling removes it
and cancels the pending timer."
  (let ((blueprint-preview-mode nil))
    (blueprint-preview-mode 1)
    (should (memq #'blueprint-preview--on-save after-save-hook))
    (blueprint-preview-mode -1)
    (should-not (memq #'blueprint-preview--on-save after-save-hook))
    (should-not blueprint-preview--timer)))

(ert-deftest blueprint-test-preview/save-schedules-debounced-update ()
  "Saving a project Org file schedules exactly one update after
`blueprint-preview-delay'; a second save reschedules instead of
stacking."
  (blueprint-test--with-project
    (let* ((calls 0)
           (blueprint--preview-stub
            (lambda ()
              (setq calls (1+ calls))
              "/tmp/does-not-matter.svg")))
      (cl-letf (((symbol-function 'blueprint--dashboard-svg-generate)
                 blueprint--preview-stub)
                (blueprint-preview--timer nil))
        (blueprint-preview-mode 1)
        (unwind-protect
            (with-temp-buffer
              (setq buffer-file-name
                    (expand-file-name "master.org" default-directory))
              (blueprint-preview--on-save)
              (blueprint-preview--on-save)
              ;; One pending timer, not two.
              (should (timerp blueprint-preview--timer))
              ;; Cancel the real timer (it would fire in the middle of
              ;; the suite with the wrong default-directory) and run
              ;; the update directly.
              (cancel-timer blueprint-preview--timer)
              (blueprint-preview--update)
              (should (= calls 1))
              (should (null blueprint-preview--timer)))
          (blueprint-preview-mode -1))))))

(ert-deftest blueprint-test-preview/save-outside-project-ignored ()
  "A save of a file outside a Blueprint project schedules nothing."
  (let ((tmp (make-temp-file "blueprint-noproject-" nil ".org"))
        (scheduled nil))
    (unwind-protect
        (cl-letf (((symbol-function 'blueprint--dashboard-svg-generate)
                   (lambda (&optional _) (setq scheduled t) "")))
          (with-temp-buffer
            (setq buffer-file-name tmp)
            (blueprint-preview--on-save)
            (should-not scheduled)
            (should (null blueprint-preview--timer))))
      (delete-file tmp))))

(ert-deftest blueprint-test-preview/update-refreshes-preview-buffer ()
  "The update regenerates the graph and refreshes the *Blueprint
Preview* buffer when it exists (in batch: the SVG source as text)."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (let ((blueprint-preview--timer nil)
          (buffers-before (buffer-list)))
      (unwind-protect
          (progn
            ;; The buffer only refreshes when it exists: it is
            ;; `blueprint-preview' that opens it first.
            (get-buffer-create "*Blueprint Preview*")
            (blueprint-preview--update)
            (should (file-exists-p
                     (expand-file-name "dashboard.svg" default-directory)))
            (with-current-buffer "*Blueprint Preview*"
              (should (string-match-p "<svg" (buffer-string))))
            ;; A second update refreshes the same buffer.
            (blueprint-test--write-component "other")
            (blueprint-preview--update)
            (with-current-buffer "*Blueprint Preview*"
              (should (string-match-p "other" (buffer-string)))))
        (dolist (buf (buffer-list))
          (unless (memq buf buffers-before)
            (kill-buffer buf)))))))

(ert-deftest blueprint-test-preview/missing-graphviz-warns-once ()
  "Without dot, the update warns once and then stays silent, without
ever breaking the save."
  (blueprint-test--with-project
    (let ((messages '())
          (blueprint-preview--warned nil))
      (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) nil))
                ((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) messages))))
        (blueprint-preview--update)
        (should (= 1 (length messages)))
        (should (string-match-p "Graphviz" (car messages)))
        (blueprint-preview--update)
        (should (= 1 (length messages)))))))

(provide 'blueprint-test-preview)
;;; blueprint-test-preview.el ends here
