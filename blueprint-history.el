;;; blueprint-history.el --- Metrics history for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Records the metrics of the document (health score, penalty, words,
;; marker counts) in .blueprint/metrics-history.org, one table row per
;; recording, and charts the score over time as an SVG.
;;
;; `blueprint-sync' records a row on every run (defcustom
;; `blueprint-history-on-sync') unless the last row has the same
;; values, so an unchanged project does not grow the table.  The
;; history file lives in the data directory and is not included in
;; master.org: it never enters the counts of the document.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)

(defcustom blueprint-history-on-sync t
  "When non-nil, `blueprint-sync' records a metrics history row.
Set to nil to keep the data directory untouched at every sync (for
example when the history file would be noise in version control)."
  :type 'boolean
  :group 'blueprint)

(defun blueprint--history-file ()
  "Return the path of the metrics history file, in the data directory."
  (blueprint--data-path "metrics-history.org"))

(defun blueprint--history-ensure-file ()
  "Create the metrics history file with its table skeleton, if absent.
Returns the file path."
  (let ((file (blueprint--history-file)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (concat
                 "#+TITLE: Metriche nel tempo\n\n"
                 "Una riga per ogni registrazione: `blueprint-sync' ne aggiunge\n"
                 "una quando i valori cambiano (see `blueprint-history-on-sync').\n"
                 "Grafico: `blueprint-metrics-history'.\n\n"
                 "* Registro\n\n"
                 "| Data | Score | Penalty | Words | QUESTION | TBD | FIXME | DA VAL | DA REV |\n"
                 "|------+-------+---------+-------+----------+-----+-------+--------+--------|\n"))))
    file))

(defun blueprint--history-counts (counts)
  "Return the COUNTS relevant to a history row, in its column order.
QUESTION, TBD, FIXME, DA VALIDARE and DA REVISIONARE: the order of
`blueprint--health-weights' without [FINDING], whose weight is 0."
  (list (nth 0 counts) (nth 1 counts) (nth 2 counts)
        (nth 3 counts) (nth 5 counts)))

(defun blueprint--history-current-row ()
  "Return the values of a new history row, as strings.
Date first, then score, penalty, words and the marker counts of the
document (see `blueprint--history-counts')."
  (let* ((summary (blueprint--document-health-summary))
         (counts (blueprint--history-counts (plist-get summary :counts))))
    (cons (format-time-string "%Y-%m-%d %H:%M")
          (mapcar (lambda (v) (format "%s" v))
                  (append (list (plist-get summary :score)
                                (plist-get summary :penalty)
                                (plist-get summary :words))
                          counts)))))

(defun blueprint--history-last-row ()
  "Return the cells of the last data row of the history table, or nil.
A data row begins with a date (\"| 2026-...\"); header and separator
rows do not match."
  (let ((file (blueprint--history-file)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-max))
        (when (re-search-backward "^|[ \t]*[0-9]" nil t)
          (mapcar #'string-trim
                  (split-string
                   (buffer-substring (line-beginning-position)
                                     (line-end-position))
                   "|" t "[ \t]+")))))))

;;;###autoload
(defun blueprint-history-record ()
  "Record the current document metrics in the metrics history file.
One row per call, appended to the `* Registro' table; a row with the
same values as the last one is skipped, so a project that did not
change does not grow the history.  Called by `blueprint-sync' when
`blueprint-history-on-sync' is non-nil."
  (interactive)
  (blueprint--history-ensure-file)
  (let* ((row (blueprint--history-current-row))
         (last (blueprint--history-last-row))
         (line (concat "| " (mapconcat #'identity row " | ") " |\n")))
    (if (and last (equal (cdr row) (cdr last)))
        (progn
          (message "Blueprint history: metrics unchanged, no new row")
          nil)
      (with-current-buffer (find-file-noselect (blueprint--history-file))
        (save-excursion
          (goto-char (point-max))
          (if (re-search-backward "^|" nil t)
              (forward-line 1)
            (goto-char (point-max)))
          (unless (bolp) (insert "\n"))
          (insert line))
        (save-buffer))
      (message "Blueprint history: recorded %s" (car row))
      (car row))))

(defun blueprint--history-rows (file)
  "Parse the history FILE into rows of numbers.
One list per data row: (DATE SCORE PENALTY WORDS QUESTION TBD FIXME
DA-VAL DA-REV), oldest first.  Rows that do not parse (a hand-edited
line) are left out."
  (let ((rows '()))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward "^|[ \t]*[0-9]" nil t)
        (let* ((cells (split-string
                       (buffer-substring (line-beginning-position)
                                         (line-end-position))
                       "|" t "[ \t]+"))
               (numbers (cl-remove-if-not #'numberp
                                          (mapcar #'string-to-number
                                                  (cdr cells)))))
          (when (and cells (= (length numbers) 8))
            (push (cons (car cells) numbers) rows)))))
    (nreverse rows)))

(defun blueprint--history-chart-svg (rows)
  "Return an SVG string charting the score of ROWS over time.
ROWS is the list returned by `blueprint--history-rows' (oldest
first); only the score (second element) is charted, on a 0--100
scale.  The SVG has an explicit namespace and a white background, as
`blueprint--health-svg-string'."
  (let* ((n (length rows))
         (w 640) (h 220) (m 44)
         (x0 m) (x1 (- w m)) (y0 (- h m)) (y1 m)
         (step (if (= n 1) 0 (/ (float (- x1 x0)) (max 1 (1- n)))))
         (points
          (mapconcat
           (lambda (i)
             (let* ((score (max 0 (min 100 (nth 1 (nth i rows)))))
                    (x (+ x0 (* step i)))
                    (y (- y0 (* (/ (- y0 y1) 100.0) score))))
               (format "%.1f,%.1f" x y)))
           (number-sequence 0 (1- n)) " "))
         (first-row (car rows))
         (last-row (nth (1- n) rows)))
    (format
     (concat "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>"
             "<rect x='0' y='0' width='%d' height='%d' fill='white'/>"
             "<text x='%d' y='24' font-size='14' fill='#333333'>"
             "Health score nel tempo (%d registrazioni)</text>"
             "<line x1='%d' y1='%d' x2='%d' y2='%d' stroke='#cccccc'/>"
             "<line x1='%d' y1='%d' x2='%d' y2='%d' stroke='#cccccc'/>"
             "<polyline points='%s' fill='none' stroke='#2b6cb0' stroke-width='2'/>"
             "<text x='%d' y='%d' font-size='12' fill='#333333'>%s</text>"
             "<text x='%d' y='%d' font-size='12' text-anchor='end' fill='#333333'>%s</text>"
             "<text x='%d' y='%d' font-size='12' fill='#2b6cb0'>%d/100</text>"
             "</svg>")
     w h w
     m 22 n
     x0 y0 x1 y0
     x0 y1 x1 y1
     points
     x0 (1- y0) (nth 0 first-row)
     x1 (+ y1 16) (nth 0 last-row)
     x1 (+ y1 34) (nth 1 last-row))))

;;;###autoload
(defun blueprint-metrics-history ()
  "Show the chart of the document health score over time.
The rows come from the metrics history file in the data directory
\(see `blueprint-history-record').  With no recording yet, says so."
  (interactive)
  (let ((file (blueprint--history-file)))
    (if (not (file-exists-p file))
        (message "No metrics history yet: run blueprint-sync to record the first row")
      (let* ((rows (blueprint--history-rows file))
             (svg-file (expand-file-name "metrics-history.svg"
                                         (blueprint--root))))
        (if (null rows)
            (message "The metrics history file has no rows yet")
          (with-temp-file svg-file
            (insert (blueprint--history-chart-svg rows)))
          (blueprint--show-svg-file svg-file "*Blueprint Metrics History*")
          svg-file)))))

(provide 'blueprint-history)
;;; blueprint-history.el ends here
