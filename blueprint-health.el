
;;; blueprint-health.el
(require 'blueprint-core)

(defun blueprint--component-metrics (file)
  (with-temp-buffer
    (insert-file-contents file)
    (list
     (how-many "QUESTION")
     (how-many "TBD")
     (how-many "FIXME"))))

(defun blueprint-health-score ()
  (interactive)
  (let ((score 100))
    (maphash
     (lambda (_ _)
       (pcase-let ((`(,q ,t ,f)
                    (blueprint--component-metrics
                     (blueprint--component-file _))))
         (cl-decf score (+ (* 3 q) (* 2 t) (* 4 f)))))
     (blueprint--components))
    (max 0 score)))

(defun blueprint-health-svg ()
  "Generate a gauge SVG with health score."
  (interactive)
  (let* ((score (blueprint-health-score))
         (angle (* 1.8 score)) ; 0-180
         (svg (format "<svg width='300' height='160'>
<path d='M20 140 A120 120 0 0 1 280 140' stroke='black' fill='none'/>
<line x1='150' y1='140' x2='%f' y2='%f' stroke='red'/>
<text x='120' y='30'>Health: %d</text>
</svg>"
                      (+ 150 (* 120 (cos (* pi (/ angle 180.0)))))
                      (- 140 (* 120 (sin (* pi (/ angle 180.0)))))
                      score)))
    (with-temp-file "health.svg" (insert svg))
    (find-file "health.svg")))

(provide 'blueprint-health)
