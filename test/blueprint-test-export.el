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

;;; --- blueprint-check-odt-styles ---

(defun blueprint-test--tiny-svg (dir)
  "Write a trivial valid SVG file under DIR and return its path.
Referencing this from Org content is enough to make the ODT export
emit an `OrgDisplayImage'-styled image frame, without needing a real
PlantUML render (no babel, no external `plantuml' dependency)."
  (let ((file (expand-file-name "tiny.svg" dir)))
    (with-temp-file file
      (insert "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\">"
              "<rect width=\"10\" height=\"10\"/></svg>"))
    file))

(defun blueprint-test--odt-styles-copy (dir &optional drop-style)
  "Copy Org's own bundled OrgOdtStyles.xml into DIR and return its path.
When DROP-STYLE is non-nil, strip that style's
`<style:style style:name=\"...\">...</style:style>' block first, to
build a fixture that mimics a corporate .ott template silently
missing an Org-internal style."
  (let ((dest (expand-file-name "styles.xml" dir)))
    (copy-file (expand-file-name "OrgOdtStyles.xml" org-odt-styles-dir) dest)
    (when drop-style
      (with-current-buffer (find-file-noselect dest)
        (goto-char (point-min))
        (re-search-forward
         (format "  <style:style style:name=\"%s\"[^\n]*\n\\(?:.*\n\\)*?  </style:style>\n"
                 (regexp-quote drop-style)))
        (replace-match "")
        (save-buffer)
        (kill-buffer)))
    dest))

(defun blueprint-test--write-odt-master (proj styles-file)
  "Write a minimal master.org under PROJ referencing STYLES-FILE and a
tiny SVG image, and return its path."
  (let ((master (expand-file-name "master.org" proj))
        (svg (blueprint-test--tiny-svg proj)))
    (with-temp-file master
      (insert (format "#+TITLE: Assessment Master\n#+ODT_STYLES_FILE: %S\n\n"
                      styles-file)
              "* Section\n\nSome text.\n\n"
              (format "[[file:%s]]\n\n" svg)
              "More text after the image.\n"))
    master))

(ert-deftest blueprint-test-export/odt-styles-check-errors-without-keyword ()
  "Signals a user-error when master.org has no #+ODT_STYLES_FILE:."
  (blueprint-test--with-project
    (with-temp-file (expand-file-name "master.org" default-directory)
      (insert "#+TITLE: Assessment Master\n\n* Section\n\nText.\n"))
    (should-error (blueprint-check-odt-styles) :type 'user-error)))

(ert-deftest blueprint-test-export/odt-styles-check-errors-without-unzip ()
  "Signals a user-error when `unzip' is not available."
  (blueprint-test--with-project
    (blueprint-test--write-odt-master default-directory "/nonexistent-styles.xml")
    (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
      (should-error (blueprint-check-odt-styles) :type 'user-error))))

(ert-deftest blueprint-test-export/odt-styles-check-detects-missing-style ()
  "Flags OrgDisplayImage when the custom styles file drops it and the
document actually references it (via an embedded image)."
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (styles (blueprint-test--odt-styles-copy proj "OrgDisplayImage")))
      (blueprint-test--write-odt-master proj styles)
      (let ((buffers-before (buffer-list)))
        (unwind-protect
            (progn
              (blueprint-check-odt-styles)
              (with-current-buffer "*Blueprint ODT Styles*"
                (should (string-match-p "OrgDisplayImage" (buffer-string)))))
          (let ((kill-buffer-query-functions nil))
            (dolist (buf (buffer-list))
              (unless (memq buf buffers-before)
                (kill-buffer buf)))))))))

(ert-deftest blueprint-test-export/odt-styles-check-no-false-positive ()
  "Reports nothing missing when the custom styles file is the real,
unmodified OrgOdtStyles.xml -- regression test for the \"Sect1\"-style
false positive: some references (Org's own table-of-contents
scaffolding) have no explicit definition even in a stock export, and
must not be flagged just because they lack a definition."
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (styles (blueprint-test--odt-styles-copy proj)))
      (blueprint-test--write-odt-master proj styles)
      (let (captured)
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (setq captured (apply #'format fmt args)))))
          (blueprint-check-odt-styles))
        (should (string-match-p "no missing" captured))))))

(ert-deftest blueprint-test-export/odt-missing-styles-reports-page-break ()
  "PageBreak is reported when referenced and undefined, even outside Org's baseline."
  (should (equal '("PageBreak")
                 (blueprint--odt-missing-styles
                  '("PageBreak" "Sect1" "OrgCode") '("OrgCode") '("OrgCode")))))

(ert-deftest blueprint-test-export/odt-missing-styles-page-break-defined ()
  "A defined PageBreak is not reported."
  (should-not (blueprint--odt-missing-styles
               '("PageBreak") '("OrgCode") '("PageBreak"))))

(provide 'blueprint-test-export)
;;; blueprint-test-export.el ends here
