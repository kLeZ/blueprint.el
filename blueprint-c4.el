;;; blueprint-c4.el --- C4 diagram generation for Blueprint  -*- lexical-binding:t; -*-

(require 'blueprint-core)

(defun blueprint--org-keyword (file key)
  "Extract the value of Org keyword KEY from FILE.
Returns the keyword value as a string, or nil if not found."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (when (re-search-forward (format "^#\\+%s:\\s-*\\(.*\\S-\\)" key) nil t)
        (match-string 1)))))

(defun blueprint-generate-c4 ()
  "Generate a PlantUML C4 container diagram from project dependencies.
Reads BLUEPRINT_DEPENDS keywords from each component's arc42.org file
and writes the result to c4.puml in the project root."
  (interactive)
  (let ((elements '())
        (relations '())
        (root (blueprint--root)))
    (maphash
     (lambda (id _dir)
       (let* ((file (blueprint--component-file id))
              (deps (blueprint--org-keyword file "BLUEPRINT_DEPENDS")))
         (push (format "Container(%s, \"%s\", \"component\")" id id) elements)
         (when (and deps (not (string-blank-p deps)))
           (dolist (d (split-string deps))
             (push (format "Rel(%s, %s, \"uses\")" id d) relations)))))
     (blueprint--components))

    (let ((outfile (expand-file-name "c4.puml" root)))
      (with-temp-file outfile
        (insert "@startuml\n!include C4_Container.puml\n")
        (dolist (e elements) (insert e "\n"))
        (dolist (r relations) (insert r "\n"))
        (insert "@enduml\n"))
      (message "Generated %s" outfile))))

(provide 'blueprint-c4)
;;; blueprint-c4.el ends here
