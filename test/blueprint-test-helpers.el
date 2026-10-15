;;; blueprint-test-helpers.el --- Shared test utilities for Blueprint  -*- lexical-binding:t; -*-

;;; Commentary:

;; Macros and helpers shared across all Blueprint test files.
;; Each test that touches the filesystem should use
;; `blueprint-test--with-project' to get a clean temporary project.

;;; Code:

(require 'ert)
(require 'blueprint-core)

(defmacro blueprint-test--with-project (&rest body)
  "Execute BODY inside a temporary, freshly initialized Blueprint project.
The macro uses `save-current-buffer' so that find-file calls inside
the body do not leak a changed current-buffer into subsequent tests.
The temp directory is cleaned up via `unwind-protect' after BODY.

IMPORTANT: Because `default-directory' is buffer-local, any call to a
function that runs `find-file' (e.g. `blueprint-add-component',
`blueprint-adr-new') will change the current buffer and therefore
`default-directory'.  Always capture `default-directory' in a local
variable BEFORE such calls if you need the project path afterward:

  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-add-component \"foo\")
      (should (file-exists-p (expand-file-name \"...\" proj)))))"
  (declare (indent 0) (debug t))
  `(let* ((tmpdir (make-temp-file "blueprint-test-" t))
          (default-directory (file-name-as-directory tmpdir)))
     (unwind-protect
         (save-current-buffer
           ;; Initialize the project structure under the configured
           ;; data directory, so a test can let-bind
           ;; `blueprint-directory-name' around the macro.
           (let ((data (expand-file-name blueprint-directory-name tmpdir)))
             (make-directory (expand-file-name "components" data) t)
             (make-directory (expand-file-name "adr" data) t))
           ,@body)
       ;; Kill any buffers visiting files inside the temp dir
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf)
                    (string-prefix-p tmpdir (buffer-file-name buf)))
           (kill-buffer buf)))
       (delete-directory tmpdir t))))

(defun blueprint-test--write-component (name &optional content)
  "Create component NAME with CONTENT (defaults to minimal template).
Requires `default-directory' to be inside a Blueprint project.
Returns the path to the created arc42.org file."
  (let* ((dir (expand-file-name
               name
               (expand-file-name "components"
                                 (blueprint--data-dir default-directory))))
         (file (expand-file-name "arc42.org" dir))
         (body (or content
                   (concat "#+TITLE: " name "\n"
                           "#+BLUEPRINT_DEPENDS:\n\n"
                           "* Introduction\n\n"
                           "* Context and Scope\n\n"
                           "* Constraints\n\n"
                           "* Solution Strategy\n\n"
                           "* Building Blocks\n\n"
                           "* Runtime Behavior\n\n"
                           "* Deployment\n\n"
                           "* Responsibility\n\n"
                           "* Risks\n\n"
                           "* Open Questions\n\n"
                           "* Diagrams\n"))))
    (make-directory dir t)
    (with-temp-file file
      (insert body))
    file))

(defun blueprint-test--write-document (name document content)
  "Write DOCUMENT (a file name) of component NAME with CONTENT.
Returns its path."
  (let ((file (expand-file-name
               document
               (expand-file-name
                name (expand-file-name
                      "components" (blueprint--data-dir default-directory))))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert content))
    file))

(defun blueprint-test--write-file (relative content)
  "Write CONTENT to RELATIVE, a path under `default-directory'.
Creates the parent directories.  Returns the absolute path."
  (let ((file (expand-file-name relative default-directory)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert content))
    file))

(defun blueprint-test--write-master (&rest includes)
  "Write master.org with some text and one #+INCLUDE: per INCLUDES.
Each element of INCLUDES is a path relative to the project root.
Returns the path of master.org."
  (blueprint-test--write-file
   "master.org"
   (concat "#+TITLE: Doc\n\n* Parte 0\n\nIntroduzione del documento.\n\n"
           (mapconcat (lambda (inc) (format "#+INCLUDE: \"%s\" :minlevel 2\n" inc))
                      includes ""))))

(defun blueprint-test--read-file (path)
  "Return the contents of PATH as a string."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(provide 'blueprint-test-helpers)
;;; blueprint-test-helpers.el ends here
