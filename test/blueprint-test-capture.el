;;; blueprint-test-capture.el --- Tests for blueprint-capture.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Regression test for the glossary capture template's file target,
;; which used to point at the orphaned .blueprint/glossary.org instead
;; of the real glossary.org included by master.org (see the identical
;; fix in blueprint-glossary.el / blueprint-references.el).

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-capture)

(ert-deftest blueprint-test-capture/glossary-template-targets-real-file ()
  "The \"bg\" glossary capture template targets the project-root
glossary.org, not the orphaned .blueprint/glossary.org that is never
included in master.org."
  (blueprint-test--with-project
    (let* ((templates (blueprint--capture-templates))
           (bg (assoc "bg" templates))
           (target (nth 3 bg)))
      (should target)
      (should (eq (car target) 'file))
      (should (equal (cadr target)
                     (expand-file-name "glossary.org" default-directory)))
      (should-not (string-match-p "\\.blueprint" (cadr target))))))

(ert-deftest blueprint-test-capture/glossary-template-creates-real-template ()
  "The glossary capture template's file target, once created, has the
real glossary.org structure, not a bare stub."
  (blueprint-test--with-project
    (let* ((templates (blueprint--capture-templates))
           (bg (assoc "bg" templates))
           (file (cadr (nth 3 bg))))
      (should (file-exists-p file))
      (should (string-match-p "Termini di dominio"
                              (blueprint-test--read-file file))))))

(provide 'blueprint-test-capture)
;;; blueprint-test-capture.el ends here
