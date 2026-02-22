
;;; blueprint-c4.el
(require 'blueprint-core)

(defun blueprint--org-keyword (file key)
  (with-temp-buffer
    (insert-file-contents file)
    (when (re-search-forward (format "#\\+%s: \\(.*\\)" key) nil t)
      (match-string 1))))

(defun blueprint-generate-c4 ()
  "Generate PlantUML C4 diagram using real dependencies."
  (interactive)
  (let ((elements '())
        (relations '()))
    (maphash
     (lambda (id _)
       (let* ((file (blueprint--component-file id))
              (deps (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
         (push (format "Container(%s, \"%s\", \"component\")" id id) elements)
         (when deps
           (dolist (d (split-string deps))
             (push (format "Rel(%s, %s, \"uses\")" id d) relations)))))
     (blueprint--components))

    (with-temp-file "c4.puml"
      (insert "@startuml\n!include C4_Container.puml\n")
      (dolist (e elements) (insert e "\n"))
      (dolist (r relations) (insert r "\n"))
      (insert "@enduml\n"))

    (message "Generated c4.puml")))

(provide 'blueprint-c4)
