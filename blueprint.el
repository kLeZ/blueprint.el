
(require 'blueprint-core)
(require 'blueprint-c4)
(require 'blueprint-health)
(require 'blueprint-migrate)

(require 'transient)

(transient-define-prefix blueprint-menu ()
  [["Architecture"
    ("C" "generate C4" blueprint-generate-c4)]
   ["Quality"
    ("H" "health svg" blueprint-health-svg)]
   ["Templates"
    ("D" "diff" blueprint-template-diff)
    ("M" "migrate" blueprint-template-migrate)]])

(global-set-key (kbd "C-c b") #'blueprint-menu)

(provide 'blueprint)
