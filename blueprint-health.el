;;; blueprint-health.el --- Health scoring for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Calculates a quality score (0--100) by scanning component files for
;; open markers (QUESTION, TBD, FIXME) and methodology markers
;; ([DA VALIDARE], [FINDING], [DA REVISIONARE]).  Also renders the result
;; as a semicircular SVG gauge and provides commands for listing
;; unresolved methodology markers across the whole project.

;;; Code:

(require 'blueprint-core)

(defconst blueprint--technical-marker-regexps
  '("\\<QUESTION\\>" "\\<TBD\\>" "\\<FIXME\\>")
  "Regexps of the technical markers: QUESTION, TBD, FIXME.")

(defun blueprint--component-metrics (file)
  "Count quality markers in FILE.
Returns a list (questions tbds fixmes).  Only markers in exported text
count (see `blueprint--uncounted-regions'), matched case-sensitively."
  (blueprint--count-file-markers file blueprint--technical-marker-regexps))

(defun blueprint--methodology-metrics (file)
  "Count methodology markers in FILE.
Returns a list (da-validare findings da-revisionare).
Markers: [DA VALIDARE], [FINDING], [DA REVISIONARE].  Only markers
in exported text count (see `blueprint--uncounted-regions')."
  (blueprint--count-file-markers
   file '("\\[DA VALIDARE\\]" "\\[FINDING\\]" "\\[DA REVISIONARE\\]")))

;;;###autoload
(defun blueprint-health-score ()
  "Calculate aggregate health score for the current Blueprint project.
Starts at 100 and deducts points for unresolved markers:
  QUESTION: -3, TBD: -2, FIXME: -4.
  [DA VALIDARE]: -1, [FINDING]: -2, [DA REVISIONARE]: -1.
Returns an integer between 0 and 100."
  (interactive)
  (let ((score 100))
    (maphash
     (lambda (id _dir)
       (let ((file (blueprint--component-file id)))
         (pcase-let ((`(,questions ,tbds ,fixmes)
                      (blueprint--cached-metrics file #'blueprint--component-metrics))
                     (`(,da-validare ,findings ,da-revisionare)
                      (blueprint--methodology-metrics file)))
           (cl-decf score (+ (* 3 questions) (* 2 tbds) (* 4 fixmes)
                             (* 1 da-validare) (* 2 findings) (* 1 da-revisionare))))))
     (blueprint--components))
    (max 0 score)))

(defun blueprint--scan-marker-occurrences (marker)
  "Return an alist of (FILE LINE-NUM LINE-TEXT) for each MARKER occurrence.
Scans all .org files in the current Blueprint project recursively,
skipping occurrences in non-exported text (see
`blueprint--uncounted-regions')."
  (let ((root (blueprint--root))
        (results '()))
    (dolist (file (directory-files-recursively
                   root blueprint--org-file-regexp))
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (dolist (pos (blueprint--marker-positions (regexp-quote marker)))
          (goto-char pos)
          (push (list file
                      (line-number-at-pos)
                      (string-trim (buffer-substring-no-properties
                                    (line-beginning-position)
                                    (line-end-position))))
                results))))
    (nreverse results)))

(defun blueprint--display-marker-list (marker title)
  "Display a buffer listing all occurrences of MARKER with TITLE as header."
  (let ((occurrences (blueprint--scan-marker-occurrences marker))
        (bufname (format "*Blueprint: %s*" title))
        (root (blueprint--root)))
    (with-current-buffer (get-buffer-create bufname)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (format "%s\n%s\n\n" title (make-string (length title) ?=)))
      (if (null occurrences)
          (insert (format "Nessun %s trovato nel progetto.\n" marker))
        (dolist (entry occurrences)
          (pcase-let ((`(,file ,line ,text) entry))
            (let ((rel (file-relative-name file root)))
              (insert (format "  %s:%d\n    %s\n" rel line text)))))
        (insert (format "\nTotale: %d occorrenza/e\n" (length occurrences))))
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (switch-to-buffer bufname)))

;;;###autoload
(defun blueprint-list-findings ()
  "List all [FINDING] markers across the current Blueprint project.
Opens a read-only buffer with file, line number, and line content
for each occurrence."
  (interactive)
  (blueprint--display-marker-list "[FINDING]" "Blueprint Findings"))

;;;###autoload
(defun blueprint-list-unvalidated ()
  "List all [DA VALIDARE] markers across the current Blueprint project.
Opens a read-only buffer with file, line number, and line content
for each occurrence."
  (interactive)
  (blueprint--display-marker-list "[DA VALIDARE]" "Blueprint Sezioni da validare"))

(defun blueprint--health-svg-string (score)
  "Return a standalone SVG gauge document for health SCORE (0-100).
The document declares the SVG namespace (without it librsvg, browsers
and LibreOffice do not treat the file as SVG) and paints its own white
background, so the black strokes stay visible on a dark Emacs theme
and in any viewer."
  (let* ((angle (- 180 (* 1.8 score)))
         (rad (* float-pi (/ angle 180.0))))
    (format "<svg xmlns='http://www.w3.org/2000/svg' width='300' height='160' viewBox='0 0 300 160'>
<rect x='0' y='0' width='300' height='160' fill='white'/>
<path d='M20 140 A130 130 0 0 1 280 140' stroke='black' fill='none'/>
<line x1='150' y1='140' x2='%f' y2='%f' stroke='red'/>
<text x='120' y='30' font-family='sans-serif' fill='black'>Health: %d</text>
</svg>"
            (+ 150 (* 120 (cos rad)))
            (- 140 (* 120 (sin rad)))
            score)))

;;;###autoload
(defun blueprint-health-svg ()
  "Generate a gauge SVG showing the project health score.
Writes the result to health.svg in the project root and shows it in
the *Blueprint Health* buffer.  The image is created with an explicit
`svg' type (native librsvg) instead of visiting the file: `image-mode'
hands every file to ImageMagick when Emacs is built with it, and the
ImageMagick security policy of many distributions forbids SVG, which
left an empty box.  Returns the path of the written file."
  (interactive)
  (let* ((root (blueprint--root))
         (score (blueprint-health-score))
         (svg (blueprint--health-svg-string score))
         (outfile (expand-file-name "health.svg" root)))
    (with-temp-file outfile (insert svg))
    (if (and (display-images-p) (image-type-available-p 'svg))
        (with-current-buffer (get-buffer-create "*Blueprint Health*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (setq default-directory (file-name-as-directory root))
            (insert-image (create-image svg 'svg t))
            (insert (format "\n\n%s\n" outfile))
            (goto-char (point-min))
            (special-mode))
          (pop-to-buffer (current-buffer)))
      (message "Health %d/100 written to %s" score outfile))
    outfile))

(provide 'blueprint-health)
;;; blueprint-health.el ends here
