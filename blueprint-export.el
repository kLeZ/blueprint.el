;;; blueprint-export.el --- Org-native export for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; PDF, ODT, HTML, and DOCX export using the Org exporter.  DOCX export
;; requires ox-pandoc.  `blueprint-export-dispatch' hands off to Org's
;; own export menu (`org-export-dispatch') for any backend and any
;; per-file template/style choice Org already supports (e.g. an
;; #+ODT_STYLES_FILE: corporate template), instead of picking a backend
;; for the user.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-c4)
(require 'ox)
(require 'ox-odt)
(require 'ob-plantuml)

(declare-function org-pandoc-export-to-docx "ox-pandoc" (&optional async subtreep visible-only body-only ext-plist))

(defmacro blueprint--with-plantuml-export (&rest body)
  "Execute BODY with Babel/PlantUML configured for headless export.
A fresh or headless (`emacs -Q --batch') session has Babel evaluation
confirmation on and PlantUML in `jar' mode.  Without disabling the
former and switching the latter to the `plantuml' executable, every
`#+begin_src plantuml :file ...' block silently exports as a
source-code listing instead of the rendered diagram -- no error, no
warning (`org-odt-export-to-odt' and friends report success either
way).  An interactive session usually works by accident because the
user's own init.el already sets these.  Bindings here apply only for
the duration of BODY, and only for a variable still at its stock
default, so a user's own customization -- interactive or in a batch
wrapper -- is never overridden."
  (declare (indent 0) (debug t))
  `(let ((org-confirm-babel-evaluate
          (if (eq org-confirm-babel-evaluate t) nil org-confirm-babel-evaluate))
         (org-plantuml-exec-mode
          (if (eq org-plantuml-exec-mode 'jar) 'plantuml org-plantuml-exec-mode)))
     (org-babel-do-load-languages 'org-babel-load-languages '((plantuml . t)))
     ,@body))

(defcustom blueprint-export-backend 'pdf
  "Default export backend for Blueprint.
Supported values: pdf, odt, html, docx.  Override per-user (e.g. to
`odt' for a corporate ODT template via #+ODT_STYLES_FILE:) with
`:custom' in your own `use-package' block rather than changing this
default, which is shared by every Blueprint project/user."
  :type '(choice (const :tag "PDF (LaTeX)" pdf)
                 (const :tag "ODT (native Org)" odt)
                 (const :tag "HTML" html)
                 (const :tag "DOCX (Pandoc)" docx))
  :group 'blueprint)

(defun blueprint--strip-duplicate-titles (_backend)
  "Keep only the first #+TITLE keyword in the current export buffer.
Org expands #+INCLUDE verbatim, so every satellite file's own
#+TITLE (kept for standalone editing) survives into master.org's
export buffer.  Because #+TITLE has `parse' behaviour in
`org-export-options-alist', Org concatenates all of them into one
composite document title instead of keeping only the master's.

Uses `org-element' rather than a blind regex search so a #+TITLE:
line shown as sample text inside an example or source block (a
common pattern in tutorial-style Org files) is left untouched --
only real keyword nodes are removed.  Deletes from the last match
backward so earlier positions stay valid."
  (let (titles)
    (org-element-map (org-element-parse-buffer) 'keyword
      (lambda (kw)
        (when (equal (org-element-property :key kw) "TITLE")
          (push kw titles))))
    ;; TITLES is in reverse document order (last match first); keep
    ;; the true first occurrence (the last element) and delete the
    ;; rest, which are already ordered from last position to first.
    (dolist (kw (butlast titles))
      (delete-region (org-element-property :begin kw)
                      (org-element-property :end kw)))))

(add-hook 'org-export-before-parsing-functions #'blueprint--strip-duplicate-titles)

(defconst blueprint--question-keyword-regexp "QUESTION[ \t]+"
  "Keyword that `blueprint-add-question' puts at the start of a list item.")

(defun blueprint--strip-question-keywords (_backend)
  "Drop the QUESTION keyword from list items in the export buffer.
The keyword is a tracking marker (lint, health score, question
listing), not text for the reader: left in place it is printed
literally in front of every open question of the delivered document.
Only plain list items whose text starts with the keyword are touched,
so the word inside a sentence, an example or a source block survives.
Deletes from the last match backward so earlier positions stay valid."
  (let (ranges)
    (org-element-map (org-element-parse-buffer) 'item
      (lambda (item)
        (let ((begin (org-element-property :contents-begin item)))
          (when begin
            (save-excursion
              (goto-char begin)
              (when (looking-at blueprint--question-keyword-regexp)
                (push (cons begin (match-end 0)) ranges)))))))
    ;; RANGES is in reverse document order already.
    (dolist (range ranges)
      (delete-region (car range) (cdr range)))))

(add-hook 'org-export-before-parsing-functions #'blueprint--strip-question-keywords)

(defconst blueprint--result-affiliated-regexp
  "^[ \t]*#\\+\\(?:CAPTION\\|ATTR_[[:alnum:]_-]+\\)\\(?:\\[.*\\]\\)?:"
  "Affiliated keyword lines of a src block that belong to its results.
Only captions and backend attributes (#+ATTR_ODT: :width ...) are
copied: #+NAME: and #+HEADER: drive Babel itself and stay on the block.")

(defun blueprint--move-result-captions (&rest _)
  "Copy captions of src blocks exported as results onto their results.
Babel replaces a block exported with \":exports results\" (the
ob-plantuml default) by its #+RESULTS: paragraph and deletes the
block's affiliated keywords with it, so a #+CAPTION: written above
a diagram block never reached the exported document: the image came
out of the results link without a caption.  Each such block's
#+CAPTION: and #+ATTR_*: lines are inserted just before its
#+RESULTS: line, where Babel still finds the results (it looks for
the RESULTS line among the next element's affiliated keywords) and
keeps them when it re-evaluates.  Blocks with no #+RESULTS: yet
\(never evaluated) and blocks whose results already carry a caption
are left alone.

Runs as :before advice on `org-babel-exp-process-buffer', the only
point where #+INCLUDE: files are already expanded (so component files
included by master.org are covered) and Babel has not run yet: the
before-processing hook comes before include expansion, the
before-parsing hook after Babel.  It only ever edits the export copy
of the buffer."
  (let (moves)
    (org-element-map (org-element-parse-buffer) 'src-block
      (lambda (src)
        (let ((lines (seq-filter
                      (lambda (l) (string-match-p blueprint--result-affiliated-regexp l))
                      (split-string (buffer-substring-no-properties
                                     (org-element-property :begin src)
                                     (org-element-property :post-affiliated src))
                                    "\n" t))))
          (when lines
            (save-excursion
              (goto-char (org-element-property :post-affiliated src))
              (let* ((info (org-babel-get-src-block-info 'no-eval))
                     (exports (format "%s" (cdr (assq :exports (nth 2 info))))))
                (when (string-match-p "\\`results\\b" exports)
                  (let ((result (org-babel-where-is-src-block-result)))
                    (when (and result
                               (not (save-excursion
                                      (goto-char result)
                                      (org-element-property
                                       :caption (org-element-at-point)))))
                      (push (cons result (concat (mapconcat #'identity lines "\n")
                                                 "\n"))
                            moves))))))))))
    ;; Insert back to front so earlier positions stay valid.
    (dolist (m (sort moves (lambda (a b) (> (car a) (car b)))))
      (goto-char (car m))
      (insert (cdr m)))))

(advice-add 'org-babel-exp-process-buffer :before #'blueprint--move-result-captions)

(defun blueprint--master-or-error ()
  "Return the master.org path, or signal an error if it does not exist.
Run `blueprint-init' or `blueprint-sync' to create master.org first."
  (let ((file (expand-file-name "master.org" (blueprint--root))))
    (unless (file-exists-p file)
      (user-error "No master.org found; run blueprint-init or blueprint-sync first"))
    file))

;;;###autoload
(defun blueprint-export-pdf ()
  "Export master.org to PDF via the Org LaTeX exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-latex-export-to-pdf))
      (message "Exported to PDF"))))

;;;###autoload
(defun blueprint-export-odt ()
  "Export master.org to ODT via the Org native ODT exporter.
Honours whatever #+ODT_STYLES_FILE: master.org declares (e.g. a
corporate template with letterhead), since this simply calls Org's
own `org-odt-export-to-odt' -- unlike PDF via LaTeX, no separate
template mechanism is involved."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-odt-export-to-odt))
      (message "Exported to ODT"))))

;;;###autoload
(defun blueprint-export-html ()
  "Export master.org to HTML via the Org HTML exporter."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-html-export-to-html))
      (message "Exported to HTML"))))

;;;###autoload
(defun blueprint-export-docx ()
  "Export master.org to DOCX via ox-pandoc.
Requires the ox-pandoc package to be installed."
  (interactive)
  (unless (require 'ox-pandoc nil t)
    (user-error "Package ox-pandoc is required for DOCX export; install it first"))
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-pandoc-export-to-docx))
      (message "Exported to DOCX"))))

;;;###autoload
(defun blueprint-export ()
  "Export using the default backend (`blueprint-export-backend')."
  (interactive)
  (pcase blueprint-export-backend
    ('pdf (blueprint-export-pdf))
    ('odt (blueprint-export-odt))
    ('html (blueprint-export-html))
    ('docx (blueprint-export-docx))
    (_ (user-error "Unknown export backend: %s" blueprint-export-backend))))

(defconst blueprint--odt-style-reference-regexp
  "\\b[a-zA-Z]+:style-name=\"\\([^\"]+\\)\""
  "Matches any ODT XML attribute that *uses* a style, e.g.
text:style-name=\"OrgCode\" or draw:style-name=\"OrgDisplayImage\".
Group 1 is the style name.")

(defconst blueprint--odt-style-definition-regexp
  "\\bstyle:name=\"\\([^\"]+\\)\""
  "Matches any ODT XML attribute that *defines* a style, whichever
element it sits on (`<style:style style:name=...>',
`<text:list-style style:name=...>', `<style:default-style
style:name=...>', ...  the attribute name is always `style:name').
Group 1 is the style name.")

(defconst blueprint--odt-extra-required-styles '("PageBreak")
  "Styles Blueprint itself references in the ODT output.
They are not part of Org's bundled OrgOdtStyles.xml, so the baseline
comparison in `blueprint--odt-missing-styles' would never report them.
\"PageBreak\" comes from the page breaks written by `blueprint-sync'
and `blueprint-insert-page-break': without a definition in
#+ODT_STYLES_FILE: LibreOffice silently ignores the break.")

(defun blueprint--odt-missing-styles (referenced baseline-defined defined)
  "Return the styles in REFERENCED that must exist but are not DEFINED.
A referenced style counts as required when it belongs to
BASELINE-DEFINED (Org's own OrgOdtStyles.xml) or to
`blueprint--odt-extra-required-styles'; other references (e.g. Org's
table-of-contents scaffolding) are not reported."
  (cl-remove-if
   (lambda (s) (or (not (or (member s baseline-defined)
                            (member s blueprint--odt-extra-required-styles)))
                   (member s defined)))
   referenced))

(defun blueprint--odt-style-names (xml-string regexp)
  "Return the deduplicated list of style names REGEXP captures in
XML-STRING (group 1)."
  (let (names)
    (with-temp-buffer
      (insert xml-string)
      (goto-char (point-min))
      (while (re-search-forward regexp nil t)
        (push (match-string 1) names)))
    (delete-dups names)))

(defun blueprint--odt-zip-entry (odt member)
  "Return the contents of MEMBER inside the ODT zip archive as a string.
ODT is a plain zip file (the OpenDocument container format); MEMBER is
a path inside it, e.g. \"content.xml\"."
  (with-temp-buffer
    (let ((status (call-process "unzip" nil t nil "-p" odt member)))
      (unless (zerop status)
        (user-error "Could not read %s from %s (unzip exit %s)"
                    member odt status)))
    (buffer-string)))

(defun blueprint--check-odt-styles-missing ()
  "Export master.org to ODT and return the list of Org-internal style
names its #+ODT_STYLES_FILE: silently fails to define.
Pure with respect to the editor: it exports (a real file-write side
effect, unavoidable since the check depends on real export output),
prints nothing, and never exits Emacs.  `blueprint-check-odt-styles'
and `blueprint-ci-check-odt-styles' both build on this and present the
result differently, the same split as `blueprint--lint-component' vs.
`blueprint-lint'/`blueprint-ci-lint'.

Returns (MISSING . (CUSTOM-STYLES-FILE . ODT)) so callers can report
which style file and which exported .odt the result is about.
Signals a user-error if `unzip' is unavailable or master.org has no
#+ODT_STYLES_FILE: set -- see `blueprint-check-odt-styles' for why
this check exists and how it avoids false positives."
  (unless (executable-find "unzip")
    (user-error "unzip not found; required to inspect the exported .odt"))
  (let* ((file (blueprint--master-or-error))
         (custom-styles-file (blueprint--org-keyword file "ODT_STYLES_FILE")))
    (unless custom-styles-file
      (user-error "No #+ODT_STYLES_FILE: set in master.org; nothing to check"))
    (with-current-buffer (find-file-noselect file)
      (blueprint--with-plantuml-export
        (org-odt-export-to-odt)))
    (let* ((odt (concat (file-name-sans-extension file) ".odt"))
           (baseline-xml
            (with-temp-buffer
              (insert-file-contents
               (expand-file-name "OrgOdtStyles.xml" org-odt-styles-dir))
              (buffer-string)))
           (baseline-defined
            (blueprint--odt-style-names
             baseline-xml blueprint--odt-style-definition-regexp))
           (content-xml (blueprint--odt-zip-entry odt "content.xml"))
           (styles-xml (blueprint--odt-zip-entry odt "styles.xml"))
           (referenced
            (blueprint--odt-style-names
             content-xml blueprint--odt-style-reference-regexp))
           (defined
            (append (blueprint--odt-style-names
                     styles-xml blueprint--odt-style-definition-regexp)
                    (blueprint--odt-style-names
                     content-xml blueprint--odt-style-definition-regexp)))
           (missing (blueprint--odt-missing-styles
                     referenced baseline-defined defined)))
      (cons missing (cons custom-styles-file odt)))))

;;;###autoload
(defun blueprint-check-odt-styles ()
  "Check that #+ODT_STYLES_FILE: does not silently drop styles Org needs.
A #+ODT_STYLES_FILE: pointing at a corporate .ott template not derived
from Org's own export replaces `styles.xml' wholesale, including the
internal styles Org's ODT backend relies on (`OrgDisplayImage',
`OrgTable*', `OrgCode', `OrgBulletedList'/`OrgNumberedList', and more
-- defined in the bundled OrgOdtStyles.xml at `org-odt-styles-dir').
A plain corporate template does not know about these: well-known
names like \"Heading\"/\"Text body\" have an implicit LibreOffice
fallback so the document looks \"almost right\", but Org-specific
ones do not -- a PlantUML diagram included via
`#+begin_src plantuml :file x.svg' overlaps the following paragraph
instead of reserving space for it, because `OrgDisplayImage' (which
sets wrap=\"none\") is not defined anywhere.  No error or warning
appears anywhere in this chain; the defect only shows up once someone
opens the final document.

This exports master.org to ODT, then compares every style the
resulting content.xml actually references against what
`#+ODT_STYLES_FILE:' (styles.xml) and content.xml's own
automatic-styles define.  Only a style also present in the bundled
OrgOdtStyles.xml is reported: some references (e.g. \"Sect1\", part of
Org's own table-of-contents scaffolding) have no explicit definition
even in a stock, unmodified export and are harmless -- flagging every
undefined reference indiscriminately would make this check noisy on a
perfectly healthy document.

Signals a user-error if `unzip' is unavailable (required to inspect
the exported .odt) or if master.org has no #+ODT_STYLES_FILE: set.
For batch/CI use, see `blueprint-ci-check-odt-styles' in
blueprint-ci.el instead."
  (interactive)
  (let* ((result (blueprint--check-odt-styles-missing))
         (missing (car result))
         (custom-styles-file (car (cdr result)))
         (odt (cdr (cdr result))))
    (if (null missing)
        (message "blueprint-check-odt-styles: %s — no missing Org-internal styles"
                 custom-styles-file)
      (with-current-buffer (get-buffer-create "*Blueprint ODT Styles*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format
                   "%s: %d style(s) this document needs are missing from styles.xml\n\n"
                   custom-styles-file (length missing)))
          (dolist (s (sort missing #'string<))
            (insert (format "  • %s\n" s)))
          (insert (format "\nSource file: %s\n" odt)))
        (goto-char (point-min))
        (special-mode)
        (switch-to-buffer (current-buffer))))))

;;;###autoload
(defun blueprint-export-dispatch ()
  "Open master.org and hand off to Org's own export menu.
Unlike `blueprint-export', which always uses
`blueprint-export-backend', this opens the standard
`org-export-dispatch' UI on master.org so any backend Org knows
about -- and any per-file choice Org already supports, such as an
alternate #+ODT_STYLES_FILE: or #+LATEX_CLASS: -- is picked
interactively instead of fixed in advance."
  (interactive)
  (let ((file (blueprint--master-or-error)))
    (with-current-buffer (find-file-noselect file)
      (call-interactively #'org-export-dispatch))))

(provide 'blueprint-export)
;;; blueprint-export.el ends here
