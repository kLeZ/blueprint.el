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
(require 'ox-latex)
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

(ert-deftest blueprint-test-export/strip-question-keywords ()
  "The QUESTION keyword is removed from list items, the text is kept."
  (with-temp-buffer
    (org-mode)
    (insert "* Open Questions\n\n"
            "- QUESTION Who owns the refund flow?\n"
            "- A plain item mentioning QUESTION in the middle\n\n"
            "#+BEGIN_EXAMPLE\n"
            "- QUESTION sample inside an example\n"
            "#+END_EXAMPLE\n")
    (blueprint--strip-question-keywords 'odt)
    (let ((content (buffer-string)))
      (should (string-match-p "^- Who owns the refund flow\\?$" content))
      (should (string-match-p "mentioning QUESTION in the middle" content))
      (should (string-match-p "^- QUESTION sample inside an example$" content)))))

(ert-deftest blueprint-test-export/question-hook-registered ()
  "Loading blueprint-export.el registers the QUESTION-stripping hook."
  (should (memq #'blueprint--strip-question-keywords
                org-export-before-parsing-functions)))

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
    ;; Written from a buffer rather than `copy-file': in CI Org comes from
    ;; the read-only Nix store, and a copied file keeps its 0444 mode.
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "OrgOdtStyles.xml" org-odt-styles-dir))
      (when drop-style
        (goto-char (point-min))
        (re-search-forward
         (format "  <style:style style:name=\"%s\"[^\n]*\n\\(?:.*\n\\)*?  </style:style>\n"
                 (regexp-quote drop-style)))
        (replace-match ""))
      (write-region nil nil dest nil 'silent))
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

;;; --- Captions of src blocks exported as results (PLAN 9.18, 9.23) ---

(defmacro blueprint-test--in-babel-export (content &rest body)
  "Insert CONTENT in a temp Org buffer, run Babel's export pass, then BODY.
`org-babel-exp-process-buffer' is the advised function, so this runs
the caption fix exactly as an export does, in a temporary directory."
  (declare (indent 1) (debug t))
  `(let* ((dir (make-temp-file "blueprint-cap-" t))
          (default-directory (file-name-as-directory dir))
          (org-confirm-babel-evaluate nil)
          (org-export-use-babel t))
     (unwind-protect
         (with-temp-buffer
           (org-mode)
           (insert ,content)
           (org-babel-exp-process-buffer)
           ,@body)
       (delete-directory dir t))))

(defun blueprint-test--results-element ()
  "Return the element holding the #+RESULTS: line in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+RESULTS:")
    (forward-line 0)
    (org-element-at-point)))

(defconst blueprint-test--captioned-block
  (concat "* S\n\n"
          "#+CAPTION: Diagramma di contesto\n"
          "#+NAME: fig-ctx\n"
          "#+HEADER: :cache no\n"
          "#+ATTR_ODT: :width 12\n"
          "#+begin_src plantuml :file x.svg %s\n"
          "A -> B\n"
          "#+end_src\n\n"
          "%s"
          "#+RESULTS: fig-ctx\n"
          "[[file:x.svg]]\n\n"
          "Testo.\n")
  "Captioned block with existing results; format with HEADER and RESULT-CAPTION.")

(ert-deftest blueprint-test-export/caption-copied-to-results ()
  "Caption, name and ATTR lines of a results-only block land on its results."
  (blueprint-test--in-babel-export
      (format blueprint-test--captioned-block
              ":exports results :eval never-export" "")
    (let ((res (blueprint-test--results-element)))
      (should (eq 'paragraph (org-element-type res)))
      (should (org-element-property :caption res))
      (should (equal "fig-ctx" (org-element-property :name res)))
      (should (org-element-property :attr_odt res)))
    ;; The block is gone; #+HEADER: is never copied; no sentinel left.
    (should-not (string-match-p "begin_src" (buffer-string)))
    (should-not (string-match-p "#\\+HEADER:" (buffer-string)))
    (should-not (string-match-p "blueprint-result-keywords" (buffer-string)))))

(ert-deftest blueprint-test-export/caption-on-results-created-during-export ()
  "A block never evaluated gets its caption on the results Babel creates.
Regression (9.23): the caption was only moved onto existing results."
  (blueprint-test--in-babel-export
      (concat "#+CAPTION: Prima valutazione\n"
              "#+NAME: fig-new\n"
              "#+begin_src emacs-lisp :results file :file out.txt :exports results\n"
              "\"contenuto\"\n#+end_src\n\n"
              "Testo dopo.\n")
    (let ((res (blueprint-test--results-element)))
      (should (string-match-p "out\\.txt" (buffer-substring-no-properties
                                           (org-element-property :begin res)
                                           (org-element-property :end res))))
      (should (org-element-property :caption res))
      (should (equal "fig-new" (org-element-property :name res))))
    (should (= 1 (how-many "^#\\+RESULTS:" (point-min) (point-max))))
    (should-not (string-match-p "blueprint-result-keywords" (buffer-string)))))

(ert-deftest blueprint-test-export/caption-anonymous-results-reevaluated ()
  "Anonymous existing results are found and replaced once, caption kept."
  (blueprint-test--in-babel-export
      (concat "#+CAPTION: Anonimo\n"
              "#+begin_src emacs-lisp :results file :file out.txt :exports results\n"
              "\"nuovo\"\n#+end_src\n\n"
              "#+RESULTS:\n[[file:out.txt]]\n")
    (should (= 1 (how-many "^#\\+RESULTS:" (point-min) (point-max))))
    (should (org-element-property :caption (blueprint-test--results-element)))))

(ert-deftest blueprint-test-export/caption-left-on-exports-both ()
  "A block exported with its code keeps the caption on the listing only."
  (blueprint-test--in-babel-export
      (format blueprint-test--captioned-block ":exports both :eval never-export" "")
    (should (= 1 (how-many "^#\\+CAPTION:" (point-min) (point-max))))
    (should (string-match-p "begin_src" (buffer-string)))))

(ert-deftest blueprint-test-export/caption-not-added-when-results-captioned ()
  "Results that already have their own caption are left alone."
  (blueprint-test--in-babel-export
      (format blueprint-test--captioned-block
              ":exports results :eval never-export"
              "#+CAPTION: Didascalia propria\n")
    (should (= 1 (how-many "^#\\+CAPTION:" (point-min) (point-max))))
    (should (string-match-p "Didascalia propria" (buffer-string)))))

(ert-deftest blueprint-test-export/caption-sentinel-removed-without-results ()
  "A block Babel does not evaluate and that has no results leaves no trace."
  (blueprint-test--in-babel-export
      (concat "#+CAPTION: Mai valutato\n"
              "#+begin_src plantuml :file never.svg :exports results :eval never-export\n"
              "A -> B\n#+end_src\n\nTesto.\n")
    (should-not (string-match-p "blueprint-result-keywords" (buffer-string)))
    (should-not (string-match-p "Mai valutato" (buffer-string)))))

(ert-deftest blueprint-test-export/caption-name-link-resolves-in-latex ()
  "A link to the block's #+NAME: points at the captioned figure in LaTeX."
  (let* ((dir (make-temp-file "blueprint-cap-" t))
         (default-directory (file-name-as-directory dir))
         (org-confirm-babel-evaluate nil))
    (unwind-protect
        (let ((tex (with-temp-buffer
                     (org-mode)
                     (insert "* S\n\nVedi [[fig-ctx]].\n\n"
                             "#+CAPTION: Contesto\n#+NAME: fig-ctx\n"
                             "#+begin_src plantuml :file ctx.png :exports results :eval never-export\n"
                             "A -> B\n#+end_src\n\n"
                             "#+RESULTS: fig-ctx\n[[file:ctx.png]]\n")
                     (org-export-as 'latex nil nil t))))
          ;; ox-latex puts the label inside the caption:
          ;; \caption{\label{fig:...}Contesto}
          (should (string-match "\\\\caption{\\\\label{\\([^}]+\\)}Contesto}" tex))
          (let ((label (match-string 1 tex)))
            (should (string-match-p (concat "\\\\ref{" (regexp-quote label) "}")
                                    tex))))
      (delete-directory dir t))))

(ert-deftest blueprint-test-export/caption-advice-installed ()
  "The caption fix runs around Babel's processing of the export buffer."
  (should (advice-member-p #'blueprint--move-result-captions
                           'org-babel-exp-process-buffer)))

(ert-deftest blueprint-test-export/odt-caption-reaches-content-xml ()
  "A caption above an included diagram block appears in the exported ODT.
Regression (pilot project, 2026-09-24): zero captions in
content.xml although every image was there."
  (skip-unless (executable-find "unzip"))
  (blueprint-test--with-project
    (let* ((proj default-directory)
           (svg (blueprint-test--tiny-svg proj))
           (arc42 (blueprint-test--write-component
                   "svc"
                   (concat "#+TITLE: svc\n\n* Diagrams\n\n"
                           "#+CAPTION: Contesto del servizio svc\n"
                           "#+begin_src plantuml :file " svg
                           " :exports results :eval never-export\nA -> B\n#+end_src\n\n"
                           "#+RESULTS:\n[[file:" svg "]]\n")))
           (master (expand-file-name "master.org" proj))
           (odt (expand-file-name "master.odt" proj)))
      (with-temp-file master
        (insert "#+TITLE: Assessment Master\n\n"
                (format "#+INCLUDE: %S :minlevel 2\n" arc42)))
      (let ((buffers-before (buffer-list)))
        (unwind-protect
            (progn
              (blueprint-export-odt)
              (should (file-exists-p odt))
              (should (string-match-p
                       "Contesto del servizio svc"
                       (with-temp-buffer
                         (call-process "unzip" nil t nil "-p" odt "content.xml")
                         (buffer-string)))))
          (let ((kill-buffer-query-functions nil))
            (dolist (buf (buffer-list))
              (unless (memq buf buffers-before)
                (kill-buffer buf)))))))))

(provide 'blueprint-test-export)
;;; blueprint-test-export.el ends here
