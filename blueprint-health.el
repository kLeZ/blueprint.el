;;; blueprint-health.el --- Health scoring for Blueprint  -*- lexical-binding:t; -*-

(require 'blueprint-core)

(defun blueprint--component-metrics (file)
  "Count quality markers in FILE.
Returns a list (questions tbds fixmes)."
  (if (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (list
         (count-matches "QUESTION" (point-min) (point-max))
         (count-matches "TBD" (point-min) (point-max))
         (count-matches "FIXME" (point-min) (point-max))))
    (list 0 0 0)))

;;;###autoload
(defun blueprint-health-score ()
  "Calculate aggregate health score for the current Blueprint project.
Starts at 100 and deducts points for quality markers:
  QUESTION: -3, TBD: -2, FIXME: -4.
Returns an integer between 0 and 100."
  (interactive)
  (let ((score 100))
    (maphash
     (lambda (id _dir)
       (pcase-let ((`(,questions ,tbds ,fixmes)
                    (blueprint--component-metrics
                     (blueprint--component-file id))))
         (cl-decf score (+ (* 3 questions) (* 2 tbds) (* 4 fixmes)))))
     (blueprint--components))
    (max 0 score)))

;;;###autoload
(defun blueprint-health-svg ()
  "Generate a gauge SVG showing the project health score.
Writes the result to health.svg in the project root."
  (interactive)
  (let* ((root (blueprint--root))
         (score (blueprint-health-score))
         (angle (* 1.8 score))
         (rad (* float-pi (/ angle 180.0)))
         (svg (format "<svg width='300' height='160'>
<path d='M20 140 A120 120 0 0 1 280 140' stroke='black' fill='none'/>
<line x1='150' y1='140' x2='%f' y2='%f' stroke='red'/>
<text x='120' y='30'>Health: %d</text>
</svg>"
                      (+ 150 (* 120 (cos rad)))
                      (- 140 (* 120 (sin rad)))
                      score))
         (outfile (expand-file-name "health.svg" root)))
    (with-temp-file outfile (insert svg))
    (find-file outfile)))

(provide 'blueprint-health)
;;; blueprint-health.el ends here
