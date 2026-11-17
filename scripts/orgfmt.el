;;; orgfmt.el --- Dev-only Org formatting script, run by fmt-docs.sh  -*- lexical-binding: t; -*-

(defun orgfmt-file (file)
  (with-current-buffer (find-file-noselect file)
    (org-mode)

    ;; align tags
    (org-align-tags 'all)

    ;; align tables
    (org-table-map-tables 'org-table-align)

    ;; indent structure
    (indent-region (point-min) (point-max))

    ;; remove trailing whitespace
    (delete-trailing-whitespace)

    ;; normalize blank lines
    (goto-char (point-min))
    (while (re-search-forward "\n\n\n+" nil t)
      (replace-match "\n\n"))

    ;; update checkbox stats
    (org-update-statistics-cookies 'all)

    ;; save only if modified
    (when (buffer-modified-p)
      (save-buffer))

    (kill-buffer)))

(defun orgfmt-tree (dir)
  (dolist (f (directory-files-recursively dir "\\.org$"))
    (orgfmt-file f)))

(orgfmt-tree ".")
