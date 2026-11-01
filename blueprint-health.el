;;; blueprint-health.el --- Health scoring for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Calculates a quality score (0--100) from the open markers left in
;; the text of the document: master.org and every file it includes with
;; #+INCLUDE:, recursively (see `blueprint--document-files').  Technical
;; markers (QUESTION, TBD, FIXME) and methodology markers ([DA VALIDARE],
;; [DA REVISIONARE]) lower it; [FINDING] is counted for the lists but
;; does not lower the score: a finding is a result of the assessment,
;; not an open point.  The weighted marker count is set against the
;; size of the exported text, so the score does not drop just because
;; the document grows (see `blueprint-health-score').  Also renders the
;; result as a semicircular SVG gauge and provides commands for listing
;; unresolved methodology markers in the document.

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

;;; --- Health score ---

(defcustom blueprint-health-words-per-point 100
  "Words of exported text that balance one penalty point.
`blueprint-health-score' is 50 when the project has one weighted
penalty point every this many words, higher with fewer points and
lower with more.  Must be a positive number."
  :type '(restricted-sexp
          :match-alternatives ((lambda (v) (and (numberp v) (> v 0)))))
  :group 'blueprint)

(defconst blueprint--health-weights
  '(("\\<QUESTION\\>"          . 3)
    ("\\<TBD\\>"               . 2)
    ("\\<FIXME\\>"             . 4)
    ("\\[DA VALIDARE\\]"       . 1)
    ("\\[FINDING\\]"           . 0)
    ("\\[DA REVISIONARE\\]"    . 1))
  "Penalty weight of each marker regexp in `blueprint-health-score'.
[FINDING] weighs 0: a finding is a result the assessment delivers,
not an open point.  It is still counted by the metrics and the
marker lists.")

(defun blueprint--document-stats (file)
  "Return (COUNTS PENALTY WORDS) for FILE, uncached.
COUNTS has one count per marker of `blueprint--health-weights', in
its order: QUESTION, TBD, FIXME, [DA VALIDARE], [FINDING],
[DA REVISIONARE].  PENALTY is the sum of each count times its
weight, WORDS the number of words of exported text (see
`blueprint--count-words-outside').  All count only outside
`blueprint--uncounted-regions', computed once.  A nil or missing FILE
yields zeros."
  (if (and file (file-exists-p file))
      (with-temp-buffer
        (blueprint--insert-org-file file)
        (let* ((regions (blueprint--uncounted-regions))
               (counts (cl-loop for (re . _weight) in blueprint--health-weights
                                collect (length (blueprint--marker-positions
                                                 re regions)))))
          (list counts
                (cl-loop for count in counts
                         for (_re . weight) in blueprint--health-weights
                         sum (* count weight))
                (blueprint--count-words-outside regions))))
    (list (make-list (length blueprint--health-weights) 0) 0 0)))

(defun blueprint--health-file-stats (file)
  "Return (PENALTY . WORDS) for FILE.
PENALTY is the sum of the markers of `blueprint--health-weights'
times their weight, WORDS the number of words of exported text (see
`blueprint--document-stats').  A nil or missing FILE yields (0 . 0)."
  (pcase-let ((`(,_counts ,penalty ,words) (blueprint--document-stats file)))
    (cons penalty words)))

(defun blueprint--health-marker-count (counts regexp)
  "Return the count of marker REGEXP in COUNTS.
COUNTS is a list in the order of `blueprint--health-weights', as
returned by `blueprint--document-stats'; REGEXP is one of its keys."
  (nth (cl-position regexp blueprint--health-weights
                    :key #'car :test #'equal)
       counts))

(defun blueprint--files-health-summary (files)
  "Return the markers of FILES, summed.
A plist with:
  :counts     summed counts, in the order of `blueprint--health-weights';
  :penalty    weighted penalty points, as in `blueprint-health-score'
              ([FINDING] weighs 0);
  :open       markers with a non-zero weight (open points);
  :words      words of exported text;
  :score      `blueprint--health-score-from' applied to :penalty and
              :words;
  :documents  a list of (PATH COUNTS PENALTY WORDS), one per file.
Per-file results go through `blueprint--cached-metrics' under the kind
`document-stats', so they do not collide with the technical marker
counts other modules cache for arc42.org."
  (let ((counts (make-list (length blueprint--health-weights) 0))
        (penalty 0) (words 0) (documents '()))
    (dolist (path files)
      (pcase-let ((`(,c ,p ,w) (blueprint--cached-metrics
                                path #'blueprint--document-stats
                                'document-stats)))
        (setq counts (cl-mapcar #'+ counts c))
        (cl-incf penalty p)
        (cl-incf words w)
        (push (list path c p w) documents)))
    (list :counts counts
          :penalty penalty
          :open (cl-loop for count in counts
                         for (_re . weight) in blueprint--health-weights
                         when (> weight 0) sum count)
          :words words
          :score (blueprint--health-score-from penalty words)
          :documents (nreverse documents))))

(defun blueprint--component-health-summary (id)
  "Return the markers of component ID across its documents.
The plist of `blueprint--files-health-summary' over the documents of
the component (arc42.org, functional.org, infrastructure.org) that
are part of the document, see `blueprint--component-included-paths'."
  (blueprint--files-health-summary (blueprint--component-included-paths id)))

(defun blueprint--unit-health-summary (unit)
  "Return the markers of UNIT, a row of `blueprint--document-units'.
See `blueprint--files-health-summary'."
  (blueprint--files-health-summary (plist-get unit :files)))

(defun blueprint--document-health-summary ()
  "Return the markers of the whole document.
`blueprint--files-health-summary' over `blueprint--document-files':
master.org and everything it includes."
  (blueprint--files-health-summary (blueprint--document-files)))

(defcustom blueprint-delivery-score-threshold 80
  "Minimum health score considered acceptable for delivery.
`blueprint-pre-delivery-check' reports WARN when the score is below
this value, and the health-colored graphs turn green at the same
score (`blueprint--health-score-color'), so the colors follow the
threshold when it is customized."
  :type 'integer
  :group 'blueprint)

(defconst blueprint--health-red-threshold 50
  "Health score below which a component is red in the graphs.
Mirrors the warning threshold of `blueprint-ci-validate' (50).  The
yellow/green threshold is `blueprint-delivery-score-threshold'.")

(defun blueprint--health-score-color (score)
  "Return the fill color for a component with health SCORE.
Red below `blueprint--health-red-threshold', yellow below
`blueprint-delivery-score-threshold', otherwise green: the yellow
threshold is the delivery threshold, so a customized one is followed."
  (cond ((< score blueprint--health-red-threshold) "#ff6b6b")
        ((< score blueprint-delivery-score-threshold) "#ffd93d")
        (t "#6bcb77")))

(defconst blueprint--not-included-color "#cccccc"
  "Fill color of a component none of whose documents is in master.org.")

(defun blueprint--component-health-color (id)
  "Return the fill color of component ID in the graphs.
`blueprint--health-score-color' of its score over the documents in
master.org, or `blueprint--not-included-color' when master.org exists
and includes none of them (a score of 100 would look clean)."
  (let ((files (blueprint--component-included-paths id)))
    (if (and (null files) (file-exists-p (blueprint--master-file)))
        blueprint--not-included-color
      (blueprint--health-score-color
       (plist-get (blueprint--files-health-summary files) :score)))))

(defun blueprint--health-component-stats ()
  "Return a list of (ID PENALTY WORDS), one per component, sorted by ID.
Each component contributes its files that are part of the document
\(see `blueprint--component-included-paths')."
  (let ((result '()))
    (maphash
     (lambda (id _dir)
       (let ((summary (blueprint--component-health-summary id)))
         (push (list id (plist-get summary :penalty) (plist-get summary :words))
               result)))
     (blueprint--components))
    (sort result (lambda (a b) (string< (car a) (car b))))))

(defun blueprint--health-score-from (penalty words)
  "Return the health score for PENALTY points over WORDS exported words.
The score is round (100 * U / (U + PENALTY)), with
U = WORDS / `blueprint-health-words-per-point', computed exactly in
integers as round (100 * WORDS / (WORDS + N * PENALTY)).  No
penalty gives 100, also with no words; penalty without words gives 0."
  (if (zerop penalty)
      100
    (let ((n blueprint-health-words-per-point))
      (if (integerp n)
          (round (* 100 words) (+ words (* n penalty)))
        (round (/ (* 100.0 words) (+ words (* n penalty))))))))

;;;###autoload
(defun blueprint-health-score ()
  "Calculate aggregate health score for the current Blueprint project.
The score covers exactly the text of the document: master.org and
every file it includes with #+INCLUDE:, recursively (see
`blueprint--document-files'), so Parte 0, I and V, glossary and
references count as much as the documents of the components.
Markers add penalty points P with these weights:
  QUESTION: 3, TBD: 2, FIXME: 4.
  [DA VALIDARE]: 1, [DA REVISIONARE]: 1, [FINDING]: 0.
P is set against the size of the same files: W words of exported
text, U = W / `blueprint-health-words-per-point'.  The score is
round (100 * U / (U + P)), so it stays the same when the document
doubles with the same ratio of markers to words.  P = 0 gives 100;
P > 0 with no words gives 0.  Markers and words count only in
exported text (see `blueprint--uncounted-regions').
Returns an integer between 0 and 100.  Interactively, also shows
the score with P and W in the echo area."
  (interactive)
  (let* ((summary (blueprint--document-health-summary))
         (score (plist-get summary :score)))
    (when (called-interactively-p 'interactive)
      (message "Health %d/100 (penalty points %d, words %d)"
               score (plist-get summary :penalty) (plist-get summary :words)))
    score))

(defun blueprint--scan-marker-occurrences (marker &optional files)
  "Return an alist of (FILE LINE-NUM LINE-TEXT) for each MARKER occurrence.
Scans FILES, by default the files of the document (see
`blueprint--document-files'), skipping occurrences in non-exported
text (see `blueprint--uncounted-regions')."
  (let ((results '()))
    (dolist (file (or files (blueprint--document-files)))
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
          (insert (format "Nessun %s trovato nel documento.\n" marker))
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
  "List all [FINDING] markers in the document.
The document is master.org and the files it includes (see
`blueprint--document-files').
Opens a read-only buffer with file, line number, and line content
for each occurrence."
  (interactive)
  (blueprint--display-marker-list "[FINDING]" "Blueprint Findings"))

;;;###autoload
(defun blueprint-list-unvalidated ()
  "List all [DA VALIDARE] markers in the document.
The document is master.org and the files it includes (see
`blueprint--document-files').
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

(defun blueprint--show-svg-file (file bufname)
  "Show the SVG image FILE in buffer BUFNAME, or report it in batch.
The image is created with an explicit `svg' type (native librsvg), as
`blueprint-health-svg' does: visiting the file would let `image-mode'
hand it to ImageMagick, whose security policy forbids SVG on many
distributions.  Without image support only a message is shown."
  (if (and (display-images-p) (image-type-available-p 'svg))
      (with-current-buffer (get-buffer-create bufname)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (setq default-directory (file-name-directory file))
          ;; From the data, not the file name: the image cache would
          ;; show a regenerated file's old content.
          (insert-image (create-image (with-temp-buffer
                                        (insert-file-contents file)
                                        (buffer-string))
                                      'svg t))
          (insert (format "\n\n%s\n" file))
          (goto-char (point-min))
          (special-mode))
        (pop-to-buffer (current-buffer)))
    (message "Generated %s" file)))

(provide 'blueprint-health)
;;; blueprint-health.el ends here
