;;; blueprint-test-upgrade.el --- Tests for blueprint-upgrade.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Project version, optional migrations and template status
;; (docs/adr/ADR-002).  Every fixture writes a layout as the code of
;; its era wrote it (verified on the git history); each step is
;; checked for its detector, its apply function, idempotence and for
;; the old format still being read without the migration.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'blueprint-test-helpers)
(require 'blueprint-upgrade)
(require 'blueprint-ci)
(require 'blueprint-dashboard)

(defun blueprint-test-upgrade--ids (&optional root)
  "Return the ids of the pending steps of ROOT."
  (mapcar (lambda (p) (plist-get (car p) :id))
          (blueprint--upgrade-pending root)))

(defmacro blueprint-test-upgrade--with-current-project (&rest body)
  "Run BODY in a temporary project with every file `blueprint-init' makes."
  (declare (indent 0) (debug t))
  `(blueprint-test--with-project
     (blueprint-init "P" "Tester")
     (let ((blueprint-history-on-sync nil)
           (blueprint-upgrade-git-check nil))
       ,@body)))

;;; --- Version file ---

(ert-deftest blueprint-test-upgrade/package-version-from-header ()
  "The package version is the Version: header of blueprint.el."
  (let ((header (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "blueprint.el" blueprint--package-dir))
                  (goto-char (point-min))
                  (re-search-forward "^;; Version: \\(.*\\)$")
                  (match-string 1))))
    (should (equal (blueprint-package-version) header))))

(ert-deftest blueprint-test-upgrade/init-records-version ()
  "`blueprint-init' writes blueprint-version.org, a new project has no
pending migration and the version is declared."
  (blueprint-test-upgrade--with-current-project
    (should (file-exists-p (blueprint--data-path "blueprint-version.org")))
    (should (equal (car (blueprint--version-read))
                   (blueprint-package-version)))
    (should (null (blueprint-test-upgrade--ids)))
    (should (equal (blueprint--project-version)
                   (cons (blueprint-package-version) 'declared)))))

(ert-deftest blueprint-test-upgrade/init-does-not-overwrite-version ()
  "Re-running `blueprint-init' on an old project does not declare it
current."
  (blueprint-test--with-project
    (blueprint--version-write "0.2.0" nil)
    (blueprint-init "P" "Tester")
    (should (equal (car (blueprint--version-read)) "0.2.0"))))

(ert-deftest blueprint-test-upgrade/unversioned-project-version-inferred ()
  "Without blueprint-version.org the version is inferred from the
oldest pending step."
  (blueprint-test--with-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (let ((v (blueprint--project-version)))
      (should (eq (cdr v) 'inferred))
      (should (string-match-p "0.2.0" (car v))))))

(ert-deftest blueprint-test-upgrade/inferred-version-is-oldest-era ()
  "The inferred version is the era of the oldest pending format, not of
the first step in apply order: a pre-0.1.0 component with a directory
named as typed is older than 0.1.0."
  (blueprint-test--with-project
    (blueprint-test--write-component
     "Order Service" "* Component\n#+BLUEPRINT_DEPENDS:\n\n** Responsibility\n")
    (should (equal (blueprint--project-version)
                   '("precedente a 0.1.0" . inferred)))))

(ert-deftest blueprint-test-upgrade/version-file-step ()
  "A project in the current format without blueprint-version.org has one
step, declaring the version; it does not change the inferred version."
  (blueprint-test-upgrade--with-current-project
    (delete-file (blueprint--version-file))
    (should (equal (blueprint-test-upgrade--ids) '("version-file")))
    (should (equal (blueprint--project-version)
                   (cons (blueprint-package-version) 'inferred)))
    (blueprint-upgrade-apply)
    (should (equal (blueprint--version-read)
                   (list (blueprint-package-version) "version-file")))))

(ert-deftest blueprint-test-upgrade/master-sections-heading-from-system-template ()
  "When the project copy of master.org's template is itself old (no
functional/infra markers), the headings come from the system template."
  (blueprint-test-upgrade--with-current-project
    (let ((master (blueprint--master-file)))
      (with-temp-file master
        (insert "#+TITLE: P\n\n* Components\n# @@blueprint-sync-start@@\n# @@blueprint-sync-end@@\n"))
      (make-directory (blueprint--data-path "templates") t)
      (with-temp-file (blueprint--data-path "templates/master.org")
        (insert "#+TITLE: {{PROJECT}}\n\n* Components\n# @@blueprint-sync-start@@\n# @@blueprint-sync-end@@\n"))
      (blueprint-upgrade-apply '("master-sync-sections"))
      (let ((content (blueprint-test--read-file master)))
        (should (string-match-p "^\\* Parte III[^\n]*\n# @@blueprint-sync-functional-start@@" content))
        (should (string-match-p "^\\* Parte IV[^\n]*\n# @@blueprint-sync-infra-start@@" content))))))

;;; --- Steps ---

(ert-deftest blueprint-test-upgrade/adr-single-file-step ()
  "One-file ADRs move into adr.org with status, date and body, their
files are removed; a second run finds nothing."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-use-pg.org"
     (concat "#+TITLE: 0001 — Use PostgreSQL\n#+DATE: 2026-02-24\n"
             "#+STATUS: accepted\n\n* Context\n\nWhy.\n\n* Decision\n\nPG.\n"))
    (should (member "adr-single-file" (blueprint-test-upgrade--ids)))
    (blueprint-upgrade-apply '("adr-single-file"))
    (should-not (blueprint--adr-legacy-files))
    (let ((adr (blueprint-test--read-file (blueprint--adr-file))))
      (should (string-match-p
               "^\\* ADR 0001: Use PostgreSQL\n:PROPERTIES:\n:STATUS: accepted\n:DATE:   2026-02-24\n:END:\n\n\\*\\* Context\n\nWhy\\."
               adr)))
    (should (equal (mapcar (lambda (e) (plist-get e :status)) (blueprint--adr-entries))
                   '("accepted")))
    (should-not (member "adr-single-file" (blueprint-test-upgrade--ids)))))

(ert-deftest blueprint-test-upgrade/glossary-sections-step ()
  "Legacy glossary terms (level 1 with a :SOURCE: drawer) move into the
first section; lookup finds them before and after."
  (blueprint-test-upgrade--with-current-project
    (let ((file (expand-file-name "glossary.org" default-directory)))
      (with-temp-file file
        (insert (blueprint-test--read-file file)
                "\n* Saga\n:PROPERTIES:\n:SOURCE: codice\n:END:\nTransazione distribuita\n"))
      (should (member "glossary-sections" (blueprint-test-upgrade--ids)))
      (let ((before (blueprint--glossary-find-term file "Saga")))
        (should (string-match-p "Transazione distribuita" before)))
      (blueprint-upgrade-apply '("glossary-sections"))
      (let ((content (blueprint-test--read-file file)))
        (should-not (string-match-p ":SOURCE:" content))
        (should (string-match-p
                 "^\\*\\* Saga\nTransazione distribuita\n/Fonte: codice/" content)))
      (should (blueprint--glossary-find-term file "Saga"))
      (should-not (member "glossary-sections" (blueprint-test-upgrade--ids))))))

(ert-deftest blueprint-test-upgrade/orphan-glossary-step ()
  "Terms in .blueprint/glossary.org (written there until 2026-09) move
into the real glossary; the orphan file goes."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/glossary.org"
     "* Saga\n:PROPERTIES:\n:SOURCE: codice\n:END:\nTransazione distribuita\n")
    (should (member "orphan-glossary" (blueprint-test-upgrade--ids)))
    (blueprint-upgrade-apply '("orphan-glossary"))
    (should-not (file-exists-p (blueprint--data-path "glossary.org")))
    (should (blueprint--glossary-find-term (blueprint--glossary-file) "Saga"))))

(ert-deftest blueprint-test-upgrade/references-steps ()
  "Old-format references, in references.org and in the orphan file,
become table rows with their type and date."
  (blueprint-test-upgrade--with-current-project
    (let ((file (blueprint--references-file)))
      (with-temp-file file
        (insert (blueprint-test--read-file file)
                "\n* Intervista CTO\n:PROPERTIES:\n:TYPE: interview\n:DATE: 2026-03-01\n:END:\nNote | utili\n"))
      (blueprint-test--write-file
       ".blueprint/references.org"
       "* Manuale operativo\n:PROPERTIES:\n:TYPE: document\n:DATE: 2026-02-28\n:END:\nv2\n")
      (let ((ids (blueprint-test-upgrade--ids)))
        (should (member "references-table-rows" ids))
        (should (member "orphan-references" ids)))
      (blueprint-upgrade-apply '("references-table-rows" "orphan-references"))
      (let ((content (blueprint-test--read-file file)))
        (should-not (string-match-p ":TYPE:" content))
        (should (string-match-p "| I-01 | Intervista CTO | \\[DA VALIDARE\\] | 2026-03-01 | Note / utili |" content))
        (should (string-match-p "| D-01 | Manuale operativo | \\[DA VALIDARE\\] | 2026-02-28 | document | v2 |" content)))
      (should-not (file-exists-p (blueprint--data-path "references.org"))))))

(ert-deftest blueprint-test-upgrade/lifecycle-keyword-step ()
  "arc42.org without #+BLUEPRINT_LIFECYCLE: gets `active' after the
header keywords; the status read does not change."
  (blueprint-test-upgrade--with-current-project
    (let ((file (blueprint-test--write-component
                 "svc" "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n#+BLUEPRINT_STATUS: in-scope\n\n* Introduction\n")))
      (should (equal (blueprint--component-lifecycle-status "svc") "active"))
      (should (member "lifecycle-keyword" (blueprint-test-upgrade--ids)))
      (blueprint-upgrade-apply '("lifecycle-keyword"))
      (should (string-match-p
               "#\\+BLUEPRINT_STATUS: in-scope\n#\\+BLUEPRINT_LIFECYCLE: active\n\n\\* Introduction"
               (blueprint-test--read-file file)))
      (should (equal (blueprint--component-lifecycle-status "svc") "active"))
      (should-not (member "lifecycle-keyword" (blueprint-test-upgrade--ids))))))

(ert-deftest blueprint-test-upgrade/component-dir-ids-step ()
  "A component directory named as typed (until 2026-02) is renamed to
its id and the master.org includes follow."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-component
     "Order Service" "#+TITLE: Order Service\n#+BLUEPRINT_LIFECYCLE: active\n\n* Introduction\n")
    (let ((master (blueprint--master-file)))
      (with-temp-file master
        (insert (blueprint-test--read-file master)
                "\n#+INCLUDE: \".blueprint/components/Order Service/arc42.org\" :minlevel 2\n"))
      (should (member "component-dir-ids" (blueprint-test-upgrade--ids)))
      (blueprint-upgrade-apply '("component-dir-ids"))
      (should (gethash "order-service" (blueprint--components)))
      (should-not (gethash "Order Service" (blueprint--components)))
      (should (string-match-p "components/order-service/arc42.org"
                              (blueprint-test--read-file master))))))

(ert-deftest blueprint-test-upgrade/pre-010-layout-step ()
  "A pre-0.1.0 component (\"* Component\" with level-2 sections) gets
the arc42 layout: sections promoted, Questions renamed, missing arc42
headings added; the text stays."
  (blueprint-test-upgrade--with-current-project
    (let ((file (blueprint-test--write-component
                 "old" "\n* Component\n#+BLUEPRINT_DEPENDS:\n\n** Responsibility\n\nPaga.\n\n** Risks\n\n** Questions\n\n- QUESTION chi?\n")))
      (should (member "component-arc42-layout" (blueprint-test-upgrade--ids)))
      (blueprint-upgrade-apply '("component-arc42-layout"))
      (let ((content (blueprint-test--read-file file)))
        (should-not (string-match-p "^\\* Component" content))
        (should (string-match-p "^\\* Responsibility\n\nPaga\\." content))
        (should (string-match-p "^\\* Open Questions\n\n- QUESTION chi\\?" content))
        (should (string-match-p "^\\* Building Blocks\n<<old-static>>" content))
        (should (string-match-p "^#\\+TITLE: old" content)))
      (should (null (blueprint--lint-component "old" file t))))))

(ert-deftest blueprint-test-upgrade/project-files-and-master-sections ()
  "A project from February 2026 (no Parts files, master.org with the
arc42 markers only) gets the missing files and sync sections; the
existing master.org text stays."
  (blueprint-test--with-project
    (let ((blueprint-upgrade-git-check nil))
      (blueprint-test--write-file
       "master.org"
       "#+TITLE: P\n\n* Components\n# @@blueprint-sync-start@@\n# @@blueprint-sync-end@@\n\n* Glossary\n")
      (blueprint-test--write-component "svc")
      (let ((ids (blueprint-test-upgrade--ids)))
        (should (member "project-files" ids))
        (should (member "master-sync-sections" ids))
        (should (member "component-documents" ids)))
      (blueprint-upgrade-apply)
      (should (file-exists-p (expand-file-name "nfr/risks.org" default-directory)))
      (should (file-exists-p (expand-file-name ".blueprint/components/svc/functional.org"
                                               default-directory)))
      (let ((master (blueprint-test--read-file (blueprint--master-file))))
        (should (string-match-p "^\\* Components\n# @@blueprint-sync-start@@" master))
        (should (string-match-p "@@blueprint-sync-functional-start@@\n# @@blueprint-sync-functional-end@@" master))
        (should (string-match-p "@@blueprint-sync-infra-start@@" master)))
      (should (null (blueprint-test-upgrade--ids)))
      (should (equal (blueprint--project-version)
                     (cons (blueprint-package-version) 'declared))))))

(ert-deftest blueprint-test-upgrade/agenda-ids-step ()
  "An agenda still keyed by the 0.3.0 IDs is a pending step; applying
it is a refresh that keeps the state."
  (blueprint-test-upgrade--with-current-project
    (require 'blueprint-agenda)
    (blueprint-test--write-component
     "alpha" "#+TITLE: alpha\n#+BLUEPRINT_LIFECYCLE: active\n\n* Open Questions\n\n- QUESTION one\n")
    (blueprint-sync)
    (blueprint-agenda-refresh)
    (let* ((entry (car (blueprint--agenda-entries)))
           (agenda (blueprint--agenda-file))
           (content (blueprint-test--read-file agenda)))
      (with-temp-file agenda
        (insert (replace-regexp-in-string
                 (concat ":ID: " (plist-get entry :id))
                 (concat ":ID: " (plist-get entry :legacy-id))
                 (replace-regexp-in-string "\\*\\* TODO" "** DONE" content t t)
                 t t)))
      (should (member "agenda-ids" (blueprint-test-upgrade--ids)))
      (blueprint-upgrade-apply '("agenda-ids"))
      (should (string-match-p "\\*\\* DONE QUESTION" (blueprint-test--read-file agenda)))
      (should-not (member "agenda-ids" (blueprint-test-upgrade--ids))))))

;;; --- Apply: backup, git, version record ---

(ert-deftest blueprint-test-upgrade/backup-and-report ()
  "Every file a step rewrites or deletes is copied to the backup
directory first, with a report."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n\nBody\n")
    (let* ((result (blueprint-upgrade-apply))
           (backup (plist-get result :backup)))
      (should (string-match-p "_archive/migration-" backup))
      (should (file-exists-p (expand-file-name ".blueprint/adr/0001-x.org" backup)))
      (should (file-exists-p (expand-file-name ".blueprint/blueprint-version.org" backup)))
      (should (string-match-p "adr-single-file"
                              (blueprint-test--read-file
                               (expand-file-name "report.org" backup)))))))

(ert-deftest blueprint-test-upgrade/backup-can-be-disabled ()
  "With `blueprint-upgrade-backup' nil no backup directory is made."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (let ((blueprint-upgrade-backup nil))
      (should (null (plist-get (blueprint-upgrade-apply) :backup)))
      (should-not (file-directory-p (expand-file-name "_archive/migration-"
                                                      default-directory))))))

(ert-deftest blueprint-test-upgrade/git-check-warn-and-refuse ()
  "Uncommitted changes: `warn' goes on with a message, `refuse' stops
before touching anything."
  (skip-unless (executable-find "git"))
  (blueprint-test-upgrade--with-current-project
    (let ((git (lambda (&rest args) (apply #'call-process "git" nil nil nil args))))
      (funcall git "init" "-q")
      (blueprint-test--write-file
       ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
      (let ((blueprint-upgrade-git-check 'refuse))
        (should-error (blueprint-upgrade-apply) :type 'user-error)
        (should (blueprint--adr-legacy-files)))
      (let ((blueprint-upgrade-git-check 'warn)
            (messages '()))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
          (blueprint-upgrade-apply))
        (should (cl-some (lambda (m) (string-match-p "uncommitted" m)) messages))
        (should-not (blueprint--adr-legacy-files))))))

(ert-deftest blueprint-test-upgrade/unsaved-buffer-blocks-migration ()
  "A file to migrate with unsaved changes in a buffer stops the
migration before anything is touched."
  (blueprint-test-upgrade--with-current-project
    (let ((file (blueprint-test--write-component
                 "svc" "#+TITLE: svc\n\n* Introduction\n")))
      (with-current-buffer (find-file-noselect file)
        (unwind-protect
            (progn
              (insert "unsaved ")
              (should-error (blueprint-upgrade-apply '("lifecycle-keyword"))
                            :type 'user-error)
              (should-not (string-match-p "BLUEPRINT_LIFECYCLE"
                                          (blueprint-test--read-file file))))
          (set-buffer-modified-p nil)
          (kill-buffer))))))

(ert-deftest blueprint-test-upgrade/partial-apply-records-migration ()
  "Applying one step records it; the version stays what it was until
nothing is pending."
  (blueprint-test-upgrade--with-current-project
    (blueprint--version-write "0.2.0" nil)
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (blueprint-test--write-component "svc" "#+TITLE: svc\n\n* Introduction\n")
    (blueprint-upgrade-apply '("adr-single-file"))
    (should (equal (blueprint--version-read) '("0.2.0" "adr-single-file")))
    (blueprint-upgrade-apply)
    (let ((v (blueprint--version-read)))
      (should (equal (car v) (blueprint-package-version)))
      (should (member "lifecycle-keyword" (cdr v)))
      (should (member "adr-single-file" (cdr v))))))

(ert-deftest blueprint-test-upgrade/detector-failure-never-breaks ()
  "A detector that signals is reported and skipped."
  (blueprint-test-upgrade--with-current-project
    (let ((blueprint-upgrade-steps
           (cons (list :id "boom" :era "x" :title "t"
                       :detect (lambda (_) (error "Kaboom"))
                       :apply #'ignore)
                 blueprint-upgrade-steps)))
      (cl-letf (((symbol-function 'message) #'ignore))
        (should (null (blueprint-test-upgrade--ids)))))))

;;; --- Templates ---

(ert-deftest blueprint-test-upgrade/template-status-classes ()
  "A copy of the current system template is current, an unmodified
older version stale, anything else customized."
  (let* ((dir (make-temp-file "bp-tpl-" t))
         (current (expand-file-name "component.org" dir))
         (old (expand-file-name "glossary.org" dir))
         (custom (expand-file-name "adr.org" dir)))
    (unwind-protect
        (progn
          (copy-file (expand-file-name "component.org" blueprint-template-dir) current)
          (with-temp-file custom (insert "my own ADR template\n"))
          ;; An older glossary.org: any history hash that is not current.
          (should (> (length (cdr (assoc "glossary.org" blueprint--template-history))) 1))
          (should (eq (blueprint--template-status current) 'current))
          (should (eq (blueprint--template-status custom) 'customized))
          (cl-letf (((symbol-function 'blueprint--file-md5)
                     (let ((orig (symbol-function 'blueprint--file-md5)))
                       (lambda (f)
                         (if (equal f old)
                             (car (cl-remove (funcall orig (expand-file-name
                                                            "glossary.org" blueprint-template-dir))
                                             (cdr (assoc "glossary.org" blueprint--template-history))
                                             :test #'equal))
                           (funcall orig f))))))
            (with-temp-file old (insert "placeholder\n"))
            (should (eq (blueprint--template-status old) 'stale))))
      (delete-directory dir t))))

(ert-deftest blueprint-test-upgrade/current-templates-are-in-history ()
  "Every system template is in the generated history table: a release
without scripts/gen-template-history.sh would classify the copies of
the new templates as customized."
  (dolist (f (directory-files blueprint-template-dir t "\\.org\\'"))
    (should (member (blueprint--file-md5 f)
                    (cdr (assoc (file-name-nondirectory f)
                                blueprint--template-history))))))

(ert-deftest blueprint-test-upgrade/stale-template-updated-with-backup ()
  "Updating a stale copy backs it up and installs the system template;
a customized copy is refused."
  (blueprint-test-upgrade--with-current-project
    (let* ((dir (blueprint--data-path "templates"))
           (file (expand-file-name "component.org" dir))
           (custom (expand-file-name "adr.org" dir)))
      (make-directory dir t)
      (with-temp-file file (insert "old version\n"))
      (with-temp-file custom (insert "custom\n"))
      (cl-letf (((symbol-function 'blueprint--template-status)
                 (lambda (f) (if (equal f file) 'stale 'customized))))
        (let ((backup (blueprint--template-update file)))
          (should (equal (blueprint-test--read-file backup) "old version\n"))
          (should-error (blueprint--template-update custom) :type 'user-error)))
      (should (equal (blueprint--file-md5 file)
                     (blueprint--file-md5 (expand-file-name "component.org"
                                                            blueprint-template-dir)))))))

;;; --- Summary, dashboard, CI ---

(ert-deftest blueprint-test-upgrade/summary-dashboard-and-json ()
  "The summary feeds the dashboard line and the JSON report."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (let ((u (blueprint--upgrade-summary)))
      (should (equal (plist-get u :pending) '("adr-single-file")))
      (should (eq (plist-get u :source) 'declared)))
    (should (string-match-p "Migrazioni disponibili: 1"
                            (blueprint--dashboard-version-part)))
    (let ((blueprint-dashboard-show-version nil))
      (should-not (blueprint--dashboard-version-part)))
    (let ((b (gethash "blueprint" (blueprint--ci-report-object))))
      (should (equal (gethash "pending-migrations" b) ["adr-single-file"]))
      (should (equal (gethash "version-source" b) "declared")))))

(ert-deftest blueprint-test-upgrade/ci-severity-configurable ()
  "A pending migration changes the CI exit code only as configured."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (dolist (case '((ignore . 0) (warn . 1) (error . 2)))
      (let ((blueprint-ci-pending-migrations (car case))
            (code nil))
        (cl-letf (((symbol-function 'kill-emacs) (lambda (c) (setq code c)))
                  ((symbol-function 'message) #'ignore)
                  ((symbol-function 'blueprint--lint-project) (lambda () nil))
                  ((symbol-function 'blueprint-health-score) (lambda () 100)))
          (let ((noninteractive t))
            (blueprint-ci-validate)))
        (should (equal code (cdr case)))))))

(ert-deftest blueprint-test-upgrade/plan-buffer-lists-steps ()
  "The plan buffer lists the pending steps and opens without changes."
  (blueprint-test-upgrade--with-current-project
    (blueprint-test--write-file
     ".blueprint/adr/0001-x.org" "#+TITLE: 0001 - X\n#+STATUS: proposed\n")
    (blueprint-project-upgrade)
    (with-current-buffer "*Blueprint Upgrade*"
      (should (eq major-mode 'blueprint-upgrade-mode))
      (should (string-match-p "adr-single-file" (buffer-string))))
    (should (blueprint--adr-legacy-files))))

;; Regression (PLAN 9.32): version-file has no :era, and a nil cell made
;; tabulated-list-print fail on every project without blueprint-version.org.
(ert-deftest blueprint-test-upgrade/plan-buffer-with-version-file-pending ()
  "The plan opens on a project without blueprint-version.org."
  (blueprint-test-upgrade--with-current-project
    (delete-file (blueprint--version-file default-directory))
    (should (assoc "version-file"
                   (mapcar (lambda (p) (cons (plist-get (car p) :id) p))
                           (blueprint--upgrade-pending default-directory))))
    (blueprint-project-upgrade)
    (with-current-buffer "*Blueprint Upgrade*"
      (should (string-match-p "version-file" (buffer-string))))))

(ert-deftest blueprint-test-upgrade/plan-entries-are-strings-for-every-step ()
  "Every column of every possible plan row is a string."
  (blueprint-test-upgrade--with-current-project
    (cl-letf (((symbol-function 'blueprint--upgrade-pending)
               (lambda (&optional _root)
                 (mapcar (lambda (step) (list step "/tmp/x.org"))
                         blueprint-upgrade-steps))))
      (dolist (entry (blueprint--upgrade-plan-entries default-directory))
        (should (cl-every #'stringp (append (cadr entry) nil)))))))

(provide 'blueprint-test-upgrade)
;;; blueprint-test-upgrade.el ends here
