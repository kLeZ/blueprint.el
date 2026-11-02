;;; blueprint-test-diff.el --- Tests for blueprint-diff.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the semantic component diff: the pure summary over unified
;; diff text and an end-to-end run against a real temporary git
;; repository.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-diff)

(ert-deftest blueprint-test-diff/summary-files-and-headings ()
  "The summary lists the touched files and the changed headings with
their level."
  (let ((s (blueprint--diff-summary
            (concat "diff --git a/.blueprint/components/svc/arc42.org b/.blueprint/components/svc/arc42.org\n"
                    "index 111..222 100644\n"
                    "--- a/.blueprint/components/svc/arc42.org\n"
                    "+++ b/.blueprint/components/svc/arc42.org\n"
                    "@@ -1,3 +1,4 @@\n"
                    " context\n"
                    "-* Old heading\n"
                    "+* New heading\n"
                    "+** Nuova sotto-sezione\n"))))
    (should (equal (plist-get s :files)
                   '(".blueprint/components/svc/arc42.org")))
    (should (member '(1 "New heading") (plist-get s :headings)))
    (should (member '(2 "Nuova sotto-sezione") (plist-get s :headings)))))

(ert-deftest blueprint-test-diff/summary-marker-deltas ()
  "Marker lines are counted per sign; headers and context are not."
  (let ((s (blueprint--diff-summary
            (concat "diff --git a/f.org b/f.org\n"
                    "--- a/f.org\n"
                    "+++ b/f.org\n"
                    "@@ -1,4 +1,4 @@\n"
                    "- QUESTION aperta\n"
                    "+ ANSWERED [2026-11-01] aperta [FONTE: x]\n"
                    "+ FIXME nuovo problema\n"
                    " context QUESTION invariata\n"
                    "+++ b/f.org\n"))))
    (let ((deltas (plist-get s :deltas)))
      (should (equal (assoc "QUESTION" deltas) '("QUESTION" 0 1)))
      (should (equal (assoc "ANSWERED" deltas) '("ANSWERED" 1 0)))
      (should (equal (assoc "FIXME" deltas) '("FIXME" 1 0)))
      (should (equal (assoc "TBD" deltas) '("TBD" 0 0))))
    (should (= (plist-get s :resolved) 1))))

(ert-deftest blueprint-test-diff/summary-empty-diff ()
  "An empty diff (no changes) sums up to nothing."
  (let ((s (blueprint--diff-summary "")))
    (should (null (plist-get s :files)))
    (should (null (plist-get s :headings)))
    (should (= (plist-get s :resolved) 0))
    (should (string-match-p "nessuno" (blueprint--diff-summary-text s)))))

(ert-deftest blueprint-test-diff/e2e-with-real-repo ()
  "End-to-end: commit, modify, diff — the buffer carries the semantic
summary and the diff body."
  (blueprint-test--with-project
    (let* ((root default-directory)
           (git (lambda (&rest args)
                  (apply #'call-process "git" nil nil nil args)))
           (arc (blueprint-test--write-component
                 "svc"
                 (concat "#+TITLE: svc\n\n* Introduction\n\n"
                         "- QUESTION vecchia\n\n"
                         "* Context and Scope\n"))))
      (funcall git "init" "-q")
      (funcall git "config" "user.email" "test@example.com")
      (funcall git "config" "user.name" "Test")
      (funcall git "add" ".")
      (funcall git "commit" "-q" "-m" "Componente iniziale")
      ;; Modify: close the question, add a FIXME.
      (with-temp-file arc
        (insert (concat "#+TITLE: svc\n\n* Introduction\n\n"
                        "- ANSWERED [2026-11-01] vecchia [FONTE: y]\n"
                        "FIXME nuovo problema\n\n"
                        "* Context and Scope\n")))
      (let ((buf (blueprint-component-diff "svc")))
        (with-current-buffer buf
          (should (eq major-mode 'diff-mode))
          (let ((text (buffer-string)))
            (should (string-match-p "QUESTION: \\+0/-1" text))
            (should (string-match-p "ANSWERED: \\+1/-0" text))
            (should (string-match-p "FIXME: \\+1/-0" text))
            (should (string-match-p "Domande risolte (righe ANSWERED nette aggiunte): 1" text))
            (should (string-match-p "^diff --git a/" text))))))))

(ert-deftest blueprint-test-diff/staged-changes-and-empty-revision ()
  "The default diff is against HEAD, so a change already staged with
`git add' still shows; an empty revision (the interactive prompt left
blank) means the default, not an argument for git."
  (blueprint-test--with-project
    (let* ((git (lambda (&rest args)
                  (apply #'call-process "git" nil nil nil args)))
           (arc (blueprint-test--write-component
                 "svc" "#+TITLE: svc\n\n* Introduction\n")))
      (funcall git "init" "-q")
      (funcall git "config" "user.email" "test@example.com")
      (funcall git "config" "user.name" "Test")
      (funcall git "add" ".")
      (funcall git "commit" "-q" "-m" "Componente iniziale")
      (with-temp-file arc
        (insert "#+TITLE: svc\n\n* Introduction\n\nFIXME staged\n"))
      (funcall git "add" ".")
      (dolist (revision '(nil ""))
        (with-current-buffer (blueprint-component-diff "svc" revision)
          (should (string-match-p "FIXME: \\+1/-0" (buffer-string))))))))

(ert-deftest blueprint-test-diff/summary-only-hunk-content ()
  "Inside a hunk an added line starting with \"++\" or a removed one
starting with \"--\" is content; outside hunks nothing is.  An
ANSWERED row merely edited closes no question."
  (let ((s (blueprint--diff-summary
            (concat "diff --git a/f.org b/f.org\n"
                    "--- a/f.org\n"
                    "+++ b/f.org\n"
                    "@@ -1,3 +1,3 @@\n"
                    "+++ FIXME in a line that starts with two pluses\n"
                    "--- TBD in a line that starts with two dashes\n"
                    "-- ANSWERED [2026-10-01] vecchia [FONTE: x]\n"
                    "+- ANSWERED [2026-10-01] vecchia, riformulata [FONTE: x]\n"))))
    (should (equal (assoc "FIXME" (plist-get s :deltas)) '("FIXME" 1 0)))
    (should (equal (assoc "TBD" (plist-get s :deltas)) '("TBD" 0 1)))
    (should (= (plist-get s :resolved) 0))))

(ert-deftest blueprint-test-diff/untracked-files-shown ()
  "A component document never added to git shows up as a new file."
  (blueprint-test--with-project
    (let ((git (lambda (&rest args)
                 (apply #'call-process "git" nil nil nil args))))
      (blueprint-test--write-component "svc" "#+TITLE: svc\n\n* Introduction\n")
      (funcall git "init" "-q")
      (funcall git "config" "user.email" "test@example.com")
      (funcall git "config" "user.name" "Test")
      (funcall git "add" ".")
      (funcall git "commit" "-q" "-m" "Componente iniziale")
      (blueprint-test--write-file ".blueprint/components/svc/functional.org"
                                  "#+TITLE: f\n\n* Area\n\n- QUESTION nuova\n")
      (with-current-buffer (blueprint-component-diff "svc")
        (let ((text (buffer-string)))
          (should (string-match-p "functional.org" text))
          (should (string-match-p "QUESTION: \\+1/-0" text)))))))

(provide 'blueprint-test-diff)
;;; blueprint-test-diff.el ends here
