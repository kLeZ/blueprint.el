;;; blueprint-test-export.el --- Tests for blueprint-export.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the duplicate-#+TITLE fix in blueprint-export.el.  Every
;; satellite file keeps its own #+TITLE for standalone editing;
;; #+INCLUDE pulls those keywords verbatim into master.org, and since
;; #+TITLE has `parse' behaviour Org concatenates all of them into one
;; composite document title unless they are stripped before export.

;;; Code:

(require 'ert)
(require 'org)
(require 'ox)
(require 'ox-html)
(require 'ox-odt)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-export)

(ert-deftest blueprint-test-export/strip-duplicate-titles ()
  "Only the first #+TITLE keyword survives in the export buffer."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Master Title\n\n"
            "* Section\n\n"
            "#+TITLE: Satellite One\n"
            "* Included heading\n\n"
            "#+TITLE: Satellite Two\n"
            "* Another included heading\n")
    (blueprint--strip-duplicate-titles 'html)
    (let ((content (buffer-string)))
      (should (string-match-p "#\\+TITLE: Master Title" content))
      (should-not (string-match-p "Satellite One" content))
      (should-not (string-match-p "Satellite Two" content)))))

(ert-deftest blueprint-test-export/strip-duplicate-titles-noop-single ()
  "A buffer with a single #+TITLE is left untouched."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Only Title\n\n* Section\n")
    (blueprint--strip-duplicate-titles 'html)
    (should (string-match-p "#\\+TITLE: Only Title" (buffer-string)))))

(ert-deftest blueprint-test-export/spares-title-inside-example-block ()
  "A #+TITLE: shown as sample text in an example block is left alone.
Tutorial-style Org files (e.g. a literate Emacs config) often show
#+TITLE: as illustrative text inside #+BEGIN_EXAMPLE, not as a real
document keyword; only actual keyword nodes should be stripped."
  (with-temp-buffer
    (org-mode)
    (insert "#+TITLE: Real Title\n\n"
            "* Section\n\n"
            "#+BEGIN_EXAMPLE\n"
            "#+TITLE: Sample Title In Example\n"
            "#+END_EXAMPLE\n")
    (blueprint--strip-duplicate-titles 'html)
    (let ((content (buffer-string)))
      (should (string-match-p "#\\+TITLE: Real Title" content))
      (should (string-match-p "#\\+TITLE: Sample Title In Example" content)))))

(ert-deftest blueprint-test-export/hook-registered ()
  "Loading blueprint-export.el registers the title-stripping hook."
  (should (memq #'blueprint--strip-duplicate-titles
                org-export-before-parsing-functions)))

(ert-deftest blueprint-test-export/master-title-after-sync ()
  "Exporting a master file with a synced #+INCLUDE keeps only its own title.
Uses a minimal master buffer (rather than the full six-part template)
so the fixture does not need every satellite file the template
includes (glossary, NFR, enterprise views, references)."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component "svc"))
           (master (expand-file-name "master.org" default-directory)))
      (with-temp-file master
        (insert "#+TITLE: Assessment Master\n\n"
                (format "#+INCLUDE: %S :minlevel 2\n" arc42)))
      (let* ((org-export-use-babel nil)
             (html (with-current-buffer (find-file-noselect master)
                     (org-export-as 'html))))
        (string-match "<title>\\([^<]*\\)</title>" html)
        (let ((title (match-string 1 html)))
          (should (string-match-p "Assessment Master" title))
          (should-not (string-match-p "svc" title)))))))

;;; --- Export backends ---

(ert-deftest blueprint-test-export/default-backend-is-pdf ()
  "The package default export backend stays PDF.
A per-user preference for ODT (e.g. to honour a corporate
#+ODT_STYLES_FILE: template) belongs in the user's own config via
`:custom', not as a change to the package-wide default shared by
every Blueprint project."
  (should (eq blueprint-export-backend 'pdf)))

(ert-deftest blueprint-test-export/master-or-error-when-missing ()
  "Export functions signal a user-error when master.org is absent."
  (blueprint-test--with-project
    (should-error (blueprint-export-odt) :type 'user-error)
    (should-error (blueprint-export-dispatch) :type 'user-error)))

(ert-deftest blueprint-test-export/odt-produces-file ()
  "blueprint-export-odt writes a real .odt file next to master.org."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component "svc"))
           (master (expand-file-name "master.org" default-directory))
           (odt (expand-file-name "master.odt" default-directory)))
      (with-temp-file master
        (insert "#+TITLE: Assessment Master\n\n"
                (format "#+INCLUDE: %S :minlevel 2\n" arc42)))
      (let ((org-export-use-babel nil))
        (blueprint-export-odt))
      (should (file-exists-p odt))
      (should (> (file-attribute-size (file-attributes odt)) 0)))))

(ert-deftest blueprint-test-export/dispatch-respects-default-backend ()
  "blueprint-export calls the ODT exporter when the default backend is odt."
  (blueprint-test--with-project
    (let* ((arc42 (blueprint-test--write-component "svc"))
           (master (expand-file-name "master.org" default-directory))
           (odt (expand-file-name "master.odt" default-directory))
           (blueprint-export-backend 'odt))
      (with-temp-file master
        (insert "#+TITLE: Assessment Master\n\n"
                (format "#+INCLUDE: %S :minlevel 2\n" arc42)))
      (let ((org-export-use-babel nil))
        (blueprint-export))
      (should (file-exists-p odt)))))

;;; --- Headless PlantUML export config ---

(ert-deftest blueprint-test-export/plantuml-export-config-applied ()
  "blueprint--with-plantuml-export disables Babel confirmation and
switches PlantUML from jar mode to the executable for its dynamic
extent, restoring both afterwards.
A headless `emacs -Q --batch' session starts with Babel confirmation
on and PlantUML in jar mode; without this, every plantuml source
block silently exports as a code listing instead of a diagram."
  (let ((org-confirm-babel-evaluate t)
        (org-plantuml-exec-mode 'jar))
    (blueprint--with-plantuml-export
      (should (eq org-confirm-babel-evaluate nil))
      (should (eq org-plantuml-exec-mode 'plantuml)))
    (should (eq org-confirm-babel-evaluate t))
    (should (eq org-plantuml-exec-mode 'jar))))

(ert-deftest blueprint-test-export/plantuml-export-preserves-custom-value ()
  "A value already customized away from the stock default is untouched."
  (let ((org-confirm-babel-evaluate 'custom-confirm-fn)
        (org-plantuml-exec-mode 'executable))
    (blueprint--with-plantuml-export
      (should (eq org-confirm-babel-evaluate 'custom-confirm-fn))
      (should (eq org-plantuml-exec-mode 'executable)))))

(ert-deftest blueprint-test-export/plantuml-export-registers-babel-language ()
  "blueprint--with-plantuml-export ensures PlantUML is a loaded Babel language."
  (blueprint--with-plantuml-export
    (should (assq 'plantuml org-babel-load-languages))))

(provide 'blueprint-test-export)
;;; blueprint-test-export.el ends here
