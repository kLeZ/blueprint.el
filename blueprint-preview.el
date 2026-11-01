;;; blueprint-preview.el --- Live dependency-graph preview for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Minor mode with a live preview of the dependency graph: on every
;; save of a project file, the health-colored SVG graph
;; (\(blueprint--dashboard-svg-generate\) is regenerated -- debounced
;; with a timer -- and the *Blueprint Preview* buffer is updated if it
;; is on display.  Nothing pops up on its own: `blueprint-preview'
;; opens the side window once and enables the mode.

;;; Code:

(require 'blueprint-core)
(require 'blueprint-health)
(require 'blueprint-dashboard)

(defcustom blueprint-preview-delay 1.0
  "Seconds to wait after the last save before regenerating the preview.
The debounce keeps a burst of saves from regenerating the graph more
than once."
  :type 'number
  :group 'blueprint)

(defvar blueprint-preview--timer nil
  "Debounce timer of `blueprint-preview-mode'.")

(defvar blueprint-preview--warned nil
  "Non-nil when the missing-Graphviz warning has been shown once.
Without `dot' installed the preview cannot render: the user is told
once per session instead of at every save.")

(defun blueprint-preview--in-project-p ()
  "Return non-nil when the current buffer's file is in a Blueprint
project and is an Org file."
  (and buffer-file-name
       (string-match-p "\\.org\\'" buffer-file-name)
       (ignore-errors (blueprint--root))))

(defun blueprint-preview--update ()
  "Regenerate the preview graph and refresh the preview buffer.
Called by the debounced timer.  Without Graphviz, warns once per
session and stays silent afterwards."
  (setq blueprint-preview--timer nil)
  (condition-case err
      (let ((svg-file (blueprint--dashboard-svg-generate))
            (buf (get-buffer "*Blueprint Preview*")))
        (when buf
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (erase-buffer)
              (if (and (display-images-p) (image-type-available-p 'svg))
                  ;; From the data, not the file name: the image cache
                  ;; would otherwise show a regenerated file's old
                  ;; content (same technique as
                  ;; `blueprint--show-svg-file').
                  (insert-image
                   (create-image
                    (with-temp-buffer
                      (insert-file-contents svg-file)
                      (buffer-string))
                    'svg t))
                (insert-file-contents svg-file)))))
        svg-file)
    (user-error
     (unless blueprint-preview--warned
       (setq blueprint-preview--warned t)
       (message "Blueprint preview: %s" (error-message-string err))))))

(defun blueprint-preview--on-save ()
  "After-save hook of `blueprint-preview-mode': debounce the update."
  (when (blueprint-preview--in-project-p)
    (when (and blueprint-preview--timer
               (timerp blueprint-preview--timer))
      (cancel-timer blueprint-preview--timer))
    (setq blueprint-preview--timer
          (run-with-timer blueprint-preview-delay nil
                          #'blueprint-preview--update))))

(define-minor-mode blueprint-preview-mode
  "Toggle the live preview of the dependency graph.
When enabled, saving any Org file of the project regenerates the
health-colored dependency graph (after `blueprint-preview-delay'
seconds) and updates the *Blueprint Preview* buffer when it exists.
`blueprint-preview' opens the preview window and enables this mode."
  :global t
  :lighter " BpPreview"
  :group 'blueprint
  (if blueprint-preview-mode
      (add-hook 'after-save-hook #'blueprint-preview--on-save)
    (remove-hook 'after-save-hook #'blueprint-preview--on-save)
    (when (and blueprint-preview--timer
               (timerp blueprint-preview--timer))
      (cancel-timer blueprint-preview--timer)
      (setq blueprint-preview--timer nil))))

;;;###autoload
(defun blueprint-preview ()
  "Open the dependency-graph preview in a side window and enable
`blueprint-preview-mode', so the graph follows the saves of the
project files.  Requires Graphviz (dot); without it, says so once and
keeps trying at every save."
  (interactive)
  (blueprint-preview-mode 1)
  (with-current-buffer (get-buffer-create "*Blueprint Preview*")
    (blueprint-preview--update)
    (special-mode))
  (set-window-buffer
   (or (get-buffer-window "*Blueprint Preview*")
       (display-buffer-in-side-window
        (get-buffer "*Blueprint Preview*")
        '((side . right) (window-width . 0.4))))
   (get-buffer "*Blueprint Preview*")))

(provide 'blueprint-preview)
;;; blueprint-preview.el ends here
