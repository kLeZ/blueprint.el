;;; blueprint-test-l10n.el --- Tests for document languages  -*- lexical-binding:t; -*-

;;; Commentary:

;; Languages of the document (docs/adr/ADR-003-localized-templates.org):
;; the project language, the templates per language, sections found
;; by property or by title in any language, the English markers with
;; the Italian ones still read, and the two upgrade steps that bring
;; an older project to the new format.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'blueprint-test-helpers)
(require 'blueprint)

(defmacro blueprint-test-l10n--with-project (lang &rest body)
  "Run BODY in a temporary project whose document language is LANG."
  (declare (indent 1) (debug t))
  `(blueprint-test--with-project
     (blueprint--version-write "0.5.0" nil nil ,lang)
     ,@body))

(defun blueprint-test-l10n--sections-of (file)
  "Return the sorted :BLUEPRINT_SECTION: values of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((ids '()))
      (goto-char (point-min))
      (while (re-search-forward "^:BLUEPRINT_SECTION:[ \t]+\\(\\S-+\\)" nil t)
        (push (match-string 1) ids))
      (sort ids #'string<))))

;;; --- Project language ---

(ert-deftest blueprint-test-l10n/project-without-keyword-is-italian ()
  "A project that declares no language is Italian, version file or not."
  (blueprint-test--with-project
    (should (equal (blueprint--project-language) "it"))
    (blueprint--version-write "0.4.1" nil)
    (should (equal (blueprint--project-language) "it"))))

(ert-deftest blueprint-test-l10n/declared-language ()
  "#+BLUEPRINT_LANGUAGE: in the version file is the project language."
  (blueprint-test-l10n--with-project "en"
    (should (equal (blueprint--project-language) "en"))))

(ert-deftest blueprint-test-l10n/version-write-keeps-language ()
  "Rewriting the version file (a migration) keeps the declared language."
  (blueprint-test-l10n--with-project "en"
    (blueprint--version-write "0.5.1" '("lifecycle-keyword"))
    (should (equal (blueprint--project-language) "en"))
    (should (string-match-p "^#\\+BLUEPRINT_LANGUAGE: en$"
                            (blueprint-test--read-file (blueprint--version-file))))))

(ert-deftest blueprint-test-l10n/init-uses-default-language ()
  "A new project gets `blueprint-default-language' and its templates."
  (blueprint-test--with-project
    (let ((blueprint-default-language "en")
          (proj default-directory))
      (blueprint-init "Acme" "Tester")
      (should (equal (blueprint--project-language proj) "en"))
      (let ((master (blueprint-test--read-file (expand-file-name "master.org" proj))))
        (should (string-match-p "^\\* Part 0 -- Preliminaries" master))
        (should-not (string-match-p "Parte 0" master)))
      (should (string-match-p "^\\* Risk register"
                              (blueprint-test--read-file
                               (expand-file-name "nfr/risks.org" proj)))))))

(ert-deftest blueprint-test-l10n/init-language-argument ()
  "The LANGUAGE argument of `blueprint-init' wins over the default."
  (blueprint-test--with-project
    (let ((blueprint-default-language "en")
          (proj default-directory))
      (blueprint-init "Acme" "Tester" "it")
      (should (equal (blueprint--project-language proj) "it"))
      (should (string-match-p "^\\* Parte 0 -- Premesse"
                              (blueprint-test--read-file
                               (expand-file-name "master.org" proj)))))))

(ert-deftest blueprint-test-l10n/init-on-old-project-keeps-italian ()
  "Re-running init on a project made before languages declares nothing."
  (blueprint-test--with-project
    (let ((blueprint-default-language "en")
          (proj default-directory))
      (blueprint-test--write-file "master.org" "#+TITLE: Vecchio\n\n* Parte 0\n")
      (blueprint-init "Acme" "Tester")
      (should (equal (blueprint--project-language proj) "it"))
      (should-not (string-match-p "BLUEPRINT_LANGUAGE"
                                  (blueprint-test--read-file
                                   (blueprint--version-file proj))))
      ;; Files created by the re-run are Italian too.
      (should (string-match-p "^\\* Registro dei rischi"
                              (blueprint-test--read-file
                               (expand-file-name "nfr/risks.org" proj)))))))

;;; --- Sections ---

(ert-deftest blueprint-test-l10n/section-found-by-property ()
  "A heading with the property is found whatever its title."
  (with-temp-buffer
    (insert "* Whatever we call it\n:PROPERTIES:\n:BLUEPRINT_SECTION: functional-areas\n:END:\n")
    (org-mode)
    (should (equal (org-element-property
                    :raw-value (blueprint--section-find 'functional-areas))
                   "Whatever we call it"))))

(defun blueprint-test-l10n--finds-title-p (title)
  "Return non-nil if a heading TITLE without property is the functional areas."
  (with-temp-buffer
    (insert (format "* Other\n\n* %s\n\n** Area\n" title))
    (org-mode)
    (blueprint--section-find 'functional-areas)))

(ert-deftest blueprint-test-l10n/section-found-by-current-or-legacy-title ()
  "Without the property: the title of the project language or the 0.4.x one.
Ignoring case; a title of another language is not enough (ADR-003,
option C: no recognition by coincidence)."
  (blueprint-test-l10n--with-project "en"
    (should (blueprint-test-l10n--finds-title-p "Functional areas"))
    (should (blueprint-test-l10n--finds-title-p "FUNCTIONAL AREAS"))
    ;; The title Blueprint 0.4.x wrote.
    (should (blueprint-test-l10n--finds-title-p "Aree funzionali")))
  (blueprint-test--with-project
    (should (blueprint-test-l10n--finds-title-p "Aree funzionali"))
    (should-not (blueprint-test-l10n--finds-title-p "Functional areas"))))

(ert-deftest blueprint-test-l10n/section-not-found-in-noexport-guide ()
  "The examples of a :noexport: guide are never a section."
  (with-temp-buffer
    (insert "* Guide :noexport:\n** Risk register\n:PROPERTIES:\n:BLUEPRINT_SECTION: risk-register\n:END:\n")
    (org-mode)
    (should-not (blueprint--section-find 'risk-register))))

;;; --- Commands in an English project ---

(ert-deftest blueprint-test-l10n/english-functional-area ()
  "In an English project an area goes under the English section, in English."
  (blueprint-test-l10n--with-project "en"
    (let ((proj default-directory))
      (blueprint-add-component "Svc")
      (blueprint-functional-add-area "svc" "Reporting")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "^\\* Functional areas\n:PROPERTIES:\n:BLUEPRINT_SECTION: functional-areas\n:END:\n\n?\\*\\* Reporting" content))
        (should (string-match-p "\\[TO VALIDATE\\]\n\nDescription of the area" content))
        (should-not (string-match-p "Aree funzionali" content))))))

(ert-deftest blueprint-test-l10n/legacy-italian-section-used-in-english-project ()
  "An Italian heading without property is found, no second section made."
  (blueprint-test-l10n--with-project "en"
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-document "svc" "functional.org"
                                      "#+TITLE: f\n\n* Aree funzionali\n\n* Entità di dominio\n")
      (blueprint-functional-add-area "svc" "Reporting")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "^\\* Aree funzionali\n\n\\*\\* Reporting" content))
        (should-not (string-match-p "Functional areas" content))))))

(ert-deftest blueprint-test-l10n/english-component-passes-structure-lint ()
  "A new English component has every arc42 section the lint expects."
  (blueprint-test-l10n--with-project "en"
    (blueprint-add-component "Svc")
    (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                         (blueprint--lint-component "svc" (blueprint--component-file "svc") t)))))

(ert-deftest blueprint-test-l10n/renamed-heading-with-property-passes-lint ()
  "A heading renamed by the user keeps satisfying the lint through its property."
  (blueprint-test-l10n--with-project "en"
    (let ((file (blueprint-test--write-component "svc")))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (re-search-forward "^\\* Introduction\n")
        (replace-match "* Purpose and goals\n:PROPERTIES:\n:BLUEPRINT_SECTION: introduction\n:END:\n")
        (write-region (point-min) (point-max) file))
      (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                           (blueprint--lint-component "svc" file t))))))

(ert-deftest blueprint-test-l10n/lint-accepts-extended-legacy-titles ()
  "A 0.4.x heading that starts with the expected title still passes the lint.
The lint matched \"^\\\\* Introduction\" as a prefix before section ids
existed: \"* Introduction and goals\" must not become a missing heading."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "svc"
                 (concat "#+TITLE: svc\n#+BLUEPRINT_DEPENDS:\n\n"
                         "* Introduction and goals\n\n* Context and Scope\n\n"
                         "* Constraints\n\n* Solution Strategy\n\n* Building Blocks\n\n"
                         "* Runtime Behavior\n\n* Deployment\n\n* Responsibility\n\n"
                         "* Risks and technical debt\n\n* Open Questions\n\n* Diagrams\n"))))
      (should-not (blueprint--lint-component "svc" file t)))))

(ert-deftest blueprint-test-l10n/property-drawers-are-not-content ()
  "A new component, whose headings carry property drawers, is still empty.
The drawers are not exported: they are neither content for the lint
nor words for the health score."
  (dolist (lang (blueprint--languages))
    (blueprint-test-l10n--with-project lang
      (blueprint-add-component "Svc")
      (let* ((dir (gethash "svc" (blueprint--components)))
             (infra (expand-file-name "infrastructure.org" dir)))
        (should (member "svc/infrastructure.org: file has no content (only headings, keywords and anchors)"
                        (blueprint--lint-content "svc/infrastructure.org" infra)))))))

(ert-deftest blueprint-test-l10n/property-drawer-words-not-counted ()
  "Adding a section property does not change the words of the score."
  (blueprint-test--with-project
    (let ((plain (blueprint-test--write-file "a.org" "* Risks\n\nSome real text here.\n"))
          (drawer (blueprint-test--write-file
                   "b.org" "* Risks\n:PROPERTIES:\n:BLUEPRINT_SECTION: risks\n:END:\n\nSome real text here.\n")))
      (should (equal (nth 2 (blueprint--document-stats (expand-file-name "a.org" default-directory)))
                     (nth 2 (blueprint--document-stats (expand-file-name "b.org" default-directory))))))))

(ert-deftest blueprint-test-l10n/missing-heading-named-in-project-language ()
  "The lint names a missing section with its title in the project language."
  (blueprint-test-l10n--with-project "en"
    (let ((file (blueprint-test--write-component "svc" "#+TITLE: svc\n\n* Introduction\n")))
      (should (member "arc42.org:svc: missing heading \"Context and scope\""
                      (blueprint--lint-component "svc" file t))))))

(ert-deftest blueprint-test-l10n/english-nfr-and-glossary ()
  "Risk, constraint, scenario and glossary entries are written in English."
  (blueprint-test-l10n--with-project "en"
    (let ((proj default-directory)
          (blueprint-glossary-source-position 'after))
      (blueprint-init "Acme" "Tester")
      (blueprint-nfr-add-risk "No DR plan" "" "High" "High")
      (blueprint-nfr-add-constraint "technical" "Java 17")
      (blueprint-nfr-add-quality-scenario "Security" "Login hardening")
      (blueprint-glossary-add "Reversal" "Cancels a payment." "interview")
      (let ((risks (blueprint-test--read-file (expand-file-name "nfr/risks.org" proj)))
            (constraints (blueprint-test--read-file (expand-file-name "nfr/constraints.org" proj)))
            (quality (blueprint-test--read-file (expand-file-name "nfr/quality-scenarios.org" proj)))
            (glossary (blueprint-test--read-file (expand-file-name "glossary.org" proj))))
        (should (string-match-p "| R-001 | No DR plan | (cross-cutting) | High | High | Critical | \\[TO VALIDATE\\]" risks))
        (should (string-match-p "| Java 17 | \\[TO VALIDATE\\]" constraints))
        (should (string-match-p "- \\*Quality attribute\\*: Security" quality))
        (should (string-match-p "\\*\\* Reversal\nCancels a payment\\.\n/Source: interview/" glossary))))))

(ert-deftest blueprint-test-l10n/risk-level-reads-every-language ()
  "Probability and impact are understood in any language."
  (blueprint-test-l10n--with-project "en"
    (should (equal (blueprint--nfr-risk-level "High" "High") "Critical"))
    (should (equal (blueprint--nfr-risk-level "Alta" "Alto") "Critical"))
    (should (equal (blueprint--nfr-risk-level "Medium" "High") "High"))
    (should (equal (blueprint--nfr-risk-level "Low" "Low") "Low")))
  (blueprint-test--with-project
    (should (equal (blueprint--nfr-risk-level "High" "High") "Critico"))))

;;; --- Markers ---

(ert-deftest blueprint-test-l10n/italian-markers-still-counted ()
  "The Italian markers of older documents count as the English ones."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component
                 "svc" "#+TITLE: svc\n\n* A\n\n[DA VALIDARE] [TO VALIDATE] [DA REVISIONARE] [TO REVIEW]\n")))
      (pcase-let ((`(,to-validate ,_findings ,to-review)
                   (blueprint--methodology-metrics file)))
        (should (= to-validate 2))
        (should (= to-review 2))))))

(ert-deftest blueprint-test-l10n/source-marker-both-forms ()
  "A question row with [SOURCE: x] or the older [FONTE: x] gives its source."
  (should (equal (nth 3 (blueprint--question-parse
                         "- ANSWERED [2026-11-16] Who? [SOURCE: CTO]"))
                 "CTO"))
  (should (equal (nth 3 (blueprint--question-parse
                         "- ANSWERED [2026-11-16] Chi? [FONTE: CTO]"))
                 "CTO")))

;;; --- Templates ---

(ert-deftest blueprint-test-l10n/every-language-has-the-same-templates ()
  "Every language folder has the same templates with the same sections."
  (let* ((names (lambda (lang)
                  (directory-files (expand-file-name lang blueprint-template-dir)
                                   nil "\\.org\\'")))
         (reference (funcall names "it")))
    (dolist (lang (blueprint--languages))
      (should (equal (funcall names lang) reference))
      (dolist (name reference)
        (should (equal (blueprint-test-l10n--sections-of
                        (expand-file-name name (expand-file-name lang blueprint-template-dir)))
                       (blueprint-test-l10n--sections-of
                        (expand-file-name name (expand-file-name "it" blueprint-template-dir)))))))))

(ert-deftest blueprint-test-l10n/templates-use-english-markers ()
  "No template writes the Italian markers any more."
  (dolist (file (directory-files-recursively blueprint-template-dir "\\.org\\'"))
    (with-temp-buffer
      (insert-file-contents file)
      (dolist (marker '("[DA VALIDARE]" "[DA REVISIONARE]" "[APPROVATO " "[FONTE:"))
        (goto-char (point-min))
        (should-not (search-forward marker nil t))))))

(defun blueprint-test-l10n--placeholders (file)
  "Return the sorted placeholders {{X}} of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((found '()))
      (goto-char (point-min))
      (while (re-search-forward "{{\\([A-Z_]+\\)}}" nil t)
        (cl-pushnew (match-string 1) found :test #'equal))
      (sort found #'string<))))

(ert-deftest blueprint-test-l10n/language-folders-match ()
  "Every language folder has the same files, strings keys and placeholders.
A translation that forgets a file, a key or a placeholder fails here."
  (let* ((folder (lambda (lang) (expand-file-name lang blueprint-template-dir)))
         (names (lambda (lang)
                  (sort (mapcar #'blueprint--template-relative-name
                                (blueprint--template-files (funcall folder lang)))
                        #'string<)))
         (reference (funcall names "it"))
         (keys (lambda (lang)
                 (mapcar #'car (blueprint--strings-parse
                                 (expand-file-name "strings.org" (funcall folder lang)))))))
    (should (member "strings.org" reference))
    (should (member "snippets/functional-feature.org" reference))
    (dolist (lang (blueprint--languages))
      (should (equal (funcall names lang) reference))
      (should (equal (funcall keys lang) (funcall keys "it")))
      (dolist (name reference)
        (should (equal (blueprint-test-l10n--placeholders
                        (expand-file-name name (funcall folder lang)))
                       (blueprint-test-l10n--placeholders
                        (expand-file-name name (funcall folder "it")))))))))

(ert-deftest blueprint-test-l10n/strings-lists-have-the-same-length ()
  "The ranked lists (probability, impact, level) have the same length
in every language: a value is read through its position."
  (dolist (key '(nfr-probabilities nfr-impacts nfr-risk-levels))
    (dolist (lang (blueprint--languages))
      (should (= (length (blueprint--l10n-list key nil lang))
                 (length (blueprint--l10n-list key nil "it")))))))

(ert-deftest blueprint-test-l10n/user-flat-templates-are-italian ()
  "The flat user directory of earlier versions serves Italian projects only."
  (let ((user (make-temp-file "blueprint-user-tpl-" t)))
    (unwind-protect
        (let ((blueprint-user-template-dir user))
          (with-temp-file (expand-file-name "component.org" user)
            (insert "my own\n"))
          (blueprint-test--with-project
            (should (equal (blueprint--resolve-template "component.org")
                           (expand-file-name "component.org" user))))
          (blueprint-test-l10n--with-project "en"
            (should (equal (blueprint--resolve-template "component.org")
                           (expand-file-name "component.org"
                                             (blueprint--system-template-dir "en"))))))
      (delete-directory user t))))

(ert-deftest blueprint-test-l10n/provisioning-respects-flat-user-templates ()
  "Provisioning Italian templates never shadows a flat customized copy."
  (let ((user (make-temp-file "blueprint-user-tpl-" t)))
    (unwind-protect
        (let ((blueprint-user-template-dir user)
              (inhibit-message t))
          (with-temp-file (expand-file-name "component.org" user)
            (insert "my own\n"))
          (blueprint--provision-user-templates "it")
          (should-not (file-exists-p (expand-file-name "it/component.org" user)))
          (should (file-exists-p (expand-file-name "it/master.org" user)))
          (blueprint--provision-user-templates "en")
          (should (file-exists-p (expand-file-name "en/component.org" user))))
      (delete-directory user t))))

(ert-deftest blueprint-test-l10n/template-status-per-language ()
  "A copy of the English system template in the user en/ folder is current."
  (let ((user (make-temp-file "blueprint-user-tpl-" t)))
    (unwind-protect
        (let ((copy (expand-file-name "en/component.org" user)))
          (make-directory (file-name-directory copy) t)
          (copy-file (expand-file-name "component.org" (blueprint--system-template-dir "en"))
                     copy)
          (should (equal (blueprint--template-language copy) "en"))
          (should (eq (blueprint--template-status copy) 'current)))
      (delete-directory user t))))

(ert-deftest blueprint-test-l10n/project-snippet-overrides-system ()
  "A skeleton in the project templates replaces the system one."
  (blueprint-test-l10n--with-project "en"
    (let ((proj default-directory))
      (blueprint-add-component "Svc")
      (let ((default-directory proj))
        (blueprint-test--write-file ".blueprint/templates/snippets/functional-area.org"
                                    "** {{NAME}}\n<<{{ANCHOR}}>>\nOur own skeleton.\n")
        (blueprint-functional-add-area "svc" "Billing"))
      (should (string-match-p "\\*\\* Billing\n<<svc-area-billing>>\nOur own skeleton\\.\n"
                              (blueprint-test--read-file
                               (expand-file-name ".blueprint/components/svc/functional.org" proj)))))))

(ert-deftest blueprint-test-l10n/strings-fall-back-key-by-key ()
  "A partial strings.org in the project overrides only its own keys."
  (blueprint-test-l10n--with-project "en"
    (blueprint-test--write-file ".blueprint/templates/strings.org"
                                "* nfr-cross-cutting\n(whole system)\n")
    (should (equal (blueprint--l10n 'nfr-cross-cutting) "(whole system)"))
    (should (equal (blueprint--l10n 'date) "Date"))))

(ert-deftest blueprint-test-l10n/user-language-from-files-only ()
  "A language folder in the user directory is a language, no code needed.
What it lacks comes from the fallback language."
  (let ((user (make-temp-file "blueprint-user-tpl-" t)))
    (unwind-protect
        (let ((blueprint-user-template-dir user))
          (make-directory (expand-file-name "fr" user))
          (with-temp-file (expand-file-name "fr/strings.org" user)
            (insert "* nfr-cross-cutting\n(transversal)\n"))
          (should (member "fr" (blueprint--languages)))
          (blueprint-test-l10n--with-project "fr"
            (should (equal (blueprint--l10n 'nfr-cross-cutting) "(transversal)"))
            (should (equal (blueprint--l10n 'date) "Date"))))
      (delete-directory user t))))

;;; --- Upgrade steps ---

(ert-deftest blueprint-test-l10n/section-properties-step ()
  "Sections of an older project get the property; the step is idempotent."
  (blueprint-test--with-project
    (let ((file (blueprint-test--write-component "svc"))
          (blueprint-upgrade-backup nil)
          (blueprint-upgrade-git-check nil))
      (should (member file (blueprint--upgrade-step-section-properties default-directory)))
      (blueprint-upgrade-apply '("section-properties"))
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "^\\* Introduction\n:PROPERTIES:\n:BLUEPRINT_SECTION: introduction\n:END:" content))
        (should (string-match-p "^\\* Open Questions\n:PROPERTIES:\n:BLUEPRINT_SECTION: open-questions\n:END:" content)))
      (should-not (blueprint--upgrade-step-section-properties default-directory))
      (should-not (cl-some (lambda (w) (string-match-p "missing heading" w))
                           (blueprint--lint-component "svc" file t))))))

(ert-deftest blueprint-test-l10n/english-markers-step ()
  "Italian markers are rewritten in English; the counts do not change."
  (blueprint-test--with-project
    (let* ((file (blueprint-test--write-component
                  "svc" "#+TITLE: svc\n\n* A\n\n[DA VALIDARE] x [DA REVISIONARE] [APPROVATO 2026-01-02]\n- ANSWERED [2026-11-01] q [FONTE: cto]\n"))
           (before (blueprint--methodology-metrics file))
           (blueprint-upgrade-backup nil)
           (blueprint-upgrade-git-check nil))
      (blueprint-test--write-file "TODO.org" "* TODO check [DA VALIDARE]\n")
      (should (member file (blueprint--upgrade-step-english-markers default-directory)))
      ;; A file of the project that Blueprint does not own is left alone.
      (should-not (member (expand-file-name "TODO.org" default-directory)
                          (blueprint--upgrade-step-english-markers default-directory)))
      (blueprint-upgrade-apply '("english-markers"))
      (let ((content (blueprint-test--read-file file)))
        (should (string-match-p "\\[TO VALIDATE\\] x \\[TO REVIEW\\] \\[APPROVED 2026-01-02\\]" content))
        (should (string-match-p "\\[SOURCE: cto\\]" content)))
      (should (equal (blueprint--methodology-metrics file) before))
      (should (string-match-p "\\[DA VALIDARE\\]"
                              (blueprint-test--read-file
                               (expand-file-name "TODO.org" default-directory))))
      (should-not (blueprint--upgrade-step-english-markers default-directory)))))

(provide 'blueprint-test-l10n)
;;; blueprint-test-l10n.el ends here
