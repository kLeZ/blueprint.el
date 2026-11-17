;;; blueprint-test-keys.el --- Tests for the menu, the command map and their docs  -*- lexical-binding:t; -*-

;;; Commentary:

;; The transient menu `blueprint-menu' and `blueprint-command-map' bind
;; the same keys to the same commands, and every key documented in
;; USAGE.org and README.org is the real one (PLAN 9.31).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'blueprint)

(defconst blueprint-test--package-dir
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Directory of the package (parent of test/).")

(defun blueprint-test--transient-bindings ()
  "Return an alist (KEY . COMMAND) of every suffix of `blueprint-menu'.
Walks the stored layout and collects every property list holding both
:key and :command, whatever the layout's shape in the installed
Transient version (the suffix plist is a sublist in older versions,
the tail of a (transient-suffix ...) list in newer ones)."
  (let ((result '()))
    (cl-labels ((walk (x)
                  (cond ((vectorp x) (mapc #'walk x))
                        ((consp x)
                         (if (and (plistp x)
                                  (stringp (plist-get x :key))
                                  (plist-get x :command))
                             (push (cons (plist-get x :key) (plist-get x :command))
                                   result)
                           (walk (car x))
                           (walk (cdr x)))))))
      (walk (get 'blueprint-menu 'transient--layout)))
    (nreverse result)))

(defun blueprint-test--transient-command (key)
  "Return the command bound to KEY in `blueprint-menu'."
  (cdr (assoc key (blueprint-test--transient-bindings))))

(ert-deftest blueprint-test-keys/graph-in-menu ()
  "The health-colored graph and the dependency graph are in the menu."
  (should (eq (blueprint-test--transient-command "h") #'blueprint-dashboard-svg))
  (should (eq (lookup-key blueprint-command-map (kbd "h")) #'blueprint-dashboard-svg))
  (should (eq (blueprint-test--transient-command "G") #'blueprint-dependency-graph))
  (should (eq (lookup-key blueprint-command-map (kbd "G"))
              #'blueprint-dependency-graph)))

(ert-deftest blueprint-test-keys/map-matches-menu ()
  "`blueprint-command-map' binds exactly the keys of `blueprint-menu'."
  (let ((menu (blueprint-test--transient-bindings))
        (map '()))
    (should (> (length menu) 40))
    (should (= (length menu) (length (delete-dups (mapcar #'car (copy-sequence menu))))))
    (map-keymap (lambda (ev cmd) (push (cons (key-description (vector ev)) cmd) map))
                blueprint-command-map)
    (should (equal (sort (copy-sequence menu) (lambda (a b) (string< (car a) (car b))))
                   (sort map (lambda (a b) (string< (car a) (car b))))))
    (dolist (b menu)
      (should (commandp (cdr b))))))

(defun blueprint-test--doc-file (name)
  "Return the contents of the package file NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name blueprint-test--package-dir))
    (buffer-string)))

(ert-deftest blueprint-test-keys/usage-keys-are-real ()
  "Every \"M-x CMD ... C-c b KEY\" of USAGE.org names the bound command.
Also every M-x blueprint-... command mentioned exists."
  (let ((text (blueprint-test--doc-file "USAGE.org"))
        (pairs 0))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward
              "M-x \\(blueprint-[[:alnum:]-]+\\)=?[ \t]+(\\(?:\\(?:oppure\\|or\\): \\)?=?C-c b \\([^ =)]+\\)"
              nil t)
        (let ((cmd (intern (match-string 1)))
              (key (match-string 2)))
          (cl-incf pairs)
          (should (equal (list cmd key (blueprint-test--transient-command key))
                         (list cmd key cmd)))
          (should (equal (list cmd key (lookup-key blueprint-command-map (kbd key)))
                         (list cmd key cmd)))))
      (goto-char (point-min))
      (while (re-search-forward "M-x \\(blueprint-[[:alnum:]-]+\\)" nil t)
        (let ((cmd (intern (match-string 1))))
          (should (equal (list cmd (fboundp cmd)) (list cmd t))))))
    (should (> pairs 20))))

(ert-deftest blueprint-test-keys/usage-bare-keys-are-bound ()
  "Every \"C-c b KEY\" of USAGE.org and README.org is a menu key."
  (dolist (doc '("USAGE.org" "README.org"))
    (let ((text (blueprint-test--doc-file doc)))
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (while (re-search-forward "C-c b \\([^ =)\n]+\\)" nil t)
          (let ((key (match-string 1)))
            (should (equal (list doc key (and (blueprint-test--transient-command key) t))
                           (list doc key t)))))))))

(ert-deftest blueprint-test-keys/readme-table-matches-menu ()
  "The key table of README.org lists every menu key, each once."
  (let ((text (blueprint-test--doc-file "README.org"))
        (keys '()))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (re-search-forward "^| Group +| Key")
      (forward-line 1)
      (while (looking-at "^|")
        (when (looking-at "^|[^|\n]*| =\\([^=]+\\)= |")
          (push (match-string 1) keys))
        (forward-line 1)))
    (should (equal (sort keys #'string<)
                   (sort (mapcar #'car (blueprint-test--transient-bindings))
                         #'string<)))))

(ert-deftest blueprint-test-keys/menu-autoload-needs-no-transient ()
  "The autoloads of the package define `blueprint-menu' with `autoload'.
A bare cookie on `transient-define-prefix' copies the whole form into
the autoloads file, which then fails with void-function when a package
manager loads it before Transient."
  ;; A fresh directory: loaddefs-generate leaves alone an output file
  ;; newer than the sources, such as an empty `make-temp-file'.
  (let* ((dir (make-temp-file "blueprint-autoloads" t))
         (out (expand-file-name "blueprint-autoloads.el" dir)))
    (unwind-protect
        (progn
          (loaddefs-generate blueprint-test--package-dir out)
          (with-temp-buffer
            (insert-file-contents out)
            (should-not (search-forward "transient-define-prefix" nil t))
            (goto-char (point-min))
            (should (search-forward "(autoload 'blueprint-menu \"blueprint\"" nil t))))
      (delete-directory dir t))))

(provide 'blueprint-test-keys)
;;; blueprint-test-keys.el ends here
