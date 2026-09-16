;;; blueprint-test-runtime.el --- Tests for blueprint-runtime.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the blueprint-runtime module that manages runtime behavior
;; flows (use case + sequence diagrams) in arc42.org components.
;;
;; NOTE: `blueprint-runtime-add-flow' calls `find-file-noselect' and
;; `switch-to-buffer', changing the current buffer and `default-directory'.
;; Always capture the project root in `proj' BEFORE calling that function.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-runtime)

;;; --- blueprint--runtime-slugify ---

(ert-deftest blueprint-test-runtime/slugify-basic ()
  "Slugify converts spaces and uppercase to hyphens and lowercase."
  (should (string= "login-flow" (blueprint--runtime-slugify "Login Flow"))))

(ert-deftest blueprint-test-runtime/slugify-special-chars ()
  "Slugify removes special characters and strips trailing hyphens."
  (should (string= "checkout-v2" (blueprint--runtime-slugify "Checkout (v2)"))))

(ert-deftest blueprint-test-runtime/slugify-collapses-hyphens ()
  "Slugify collapses consecutive hyphens."
  (should (string= "a-b" (blueprint--runtime-slugify "a  b"))))

;;; --- blueprint--runtime-list-flows ---

(ert-deftest blueprint-test-runtime/list-flows-nil-file ()
  "list-flows returns nil when file is nil."
  (should (null (blueprint--runtime-list-flows nil))))

(ert-deftest blueprint-test-runtime/list-flows-missing-file ()
  "list-flows returns nil when file does not exist."
  (should (null (blueprint--runtime-list-flows "/tmp/blueprint-nonexistent-9999.org"))))

(ert-deftest blueprint-test-runtime/list-flows-empty-section ()
  "list-flows returns nil when Runtime Behavior section has no flows."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-component "comp"
               "#+TITLE: comp\n\n* Runtime Behavior\n\n")))
      (should (null (blueprint--runtime-list-flows f))))))

(ert-deftest blueprint-test-runtime/list-flows-finds-flows ()
  "list-flows returns level-2 headings under Runtime Behavior only."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-component "comp"
               (concat "#+TITLE: comp\n\n"
                       "* Runtime Behavior\n\n"
                       "** Flusso: Login\n\nContent.\n\n"
                       "** Flusso: Checkout\n\nContent.\n\n"
                       "* Deployment\n\n"
                       "** Not a flow\n\n"))))
      (let ((flows (blueprint--runtime-list-flows f)))
        (should (member "Flusso: Login" flows))
        (should (member "Flusso: Checkout" flows))
        (should-not (member "Not a flow" flows))))))

;;; --- blueprint-runtime-add-flow ---

(ert-deftest blueprint-test-runtime/add-flow-creates-section ()
  "add-flow creates Runtime Behavior section when absent."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (blueprint--component-file "svc"))))
        (should (string-match-p "\\* Runtime Behavior" content))
        (should (string-match-p "\\*\\* Flusso: Login" content))))))

(ert-deftest blueprint-test-runtime/add-flow-under-existing-section ()
  "add-flow appends under an existing Runtime Behavior section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc"
        (concat "#+TITLE: svc\n\n"
                "* Introduction\n\nIntro.\n\n"
                "* Runtime Behavior\n\n"
                "* Deployment\n\nDeploy.\n\n"))
      (blueprint-runtime-add-flow "svc" "Pagamento")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "\\*\\* Flusso: Pagamento" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-uc-section ()
  "add-flow inserts a *** Casi d'uso sub-heading."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "Casi d'uso" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-seq-section ()
  "add-flow inserts a *** Sequenza sub-heading."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "\\*\\*\\* Sequenza" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-uc-plantuml ()
  "add-flow inserts a PlantUML block in the Casi d'uso section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "begin_src plantuml.*uc-login\\.svg" content))
        (should (string-match-p "usecase" content))
        (should (string-match-p "left to right direction" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-seq-plantuml ()
  "add-flow inserts a PlantUML sequence diagram block."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "begin_src plantuml.*seq-login\\.svg" content))
        (should (string-match-p "participant" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-anchor ()
  "add-flow inserts an org anchor based on component-id and flow slug."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "User Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "<<svc-flow-user-login>>" content))))))

(ert-deftest blueprint-test-runtime/add-flow-has-descriptions ()
  "add-flow inserts prose descriptions for both diagram sub-sections."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Checkout")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "stakeholder non tecnici" content))
        (should (string-match-p "team tecnici" content))))))

(ert-deftest blueprint-test-runtime/add-flow-multiple-flows ()
  "Multiple flows accumulate under Runtime Behavior."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (blueprint-runtime-add-flow "svc" "Checkout")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "Flusso: Login" content))
        (should (string-match-p "Flusso: Checkout" content))))))

(ert-deftest blueprint-test-runtime/add-flow-stays-before-next-section ()
  "add-flow inserts before the next level-1 section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc"
        (concat "#+TITLE: svc\n\n"
                "* Runtime Behavior\n\n"
                "* Deployment\n\nDeploy config.\n\n"))
      (blueprint-runtime-add-flow "svc" "Login")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (let ((pos-flow (string-match "Flusso: Login" content))
              (pos-deploy (string-match "\\* Deployment" content)))
          (should pos-flow)
          (should pos-deploy)
          (should (< pos-flow pos-deploy)))))))

(ert-deftest blueprint-test-runtime/add-flow-unknown-component ()
  "add-flow signals error for unknown component."
  (blueprint-test--with-project
    (should-error (blueprint-runtime-add-flow "ghost" "Login") :type 'user-error)))

;;; --- blueprint-runtime-add-process ---

(ert-deftest blueprint-test-runtime/add-process-creates-section ()
  "add-process creates Processi di business section when absent."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-process "svc" "Onboarding cliente")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "\\* Processi di business" content))
        (should (string-match-p "\\*\\* Processo: Onboarding cliente" content))))))

(ert-deftest blueprint-test-runtime/add-process-under-existing-section ()
  "add-process appends under an existing Processi di business section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc"
        (concat "#+TITLE: svc\n\n"
                "* Introduction\n\nIntro.\n\n"
                "* Processi di business\n\n"
                "* Deployment\n\nDeploy.\n\n"))
      (blueprint-runtime-add-process "svc" "Reso prodotto")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "\\*\\* Processo: Reso prodotto" content))))))

(ert-deftest blueprint-test-runtime/add-process-has-swimlane-plantuml ()
  "add-process inserts a PlantUML activity diagram with swimlanes."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-process "svc" "Onboarding")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "begin_src plantuml.*process-onboarding\\.svg" content))
        (should (string-match-p "|Attore 1|" content))
        (should (string-match-p "|Attore 2|" content))
        (should (string-match-p "start" content))
        (should (string-match-p "stop" content))))))

(ert-deftest blueprint-test-runtime/add-process-has-anchor ()
  "add-process inserts an org anchor based on component-id and process slug."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-process "svc" "Gestione reso")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "<<svc-process-gestione-reso>>" content))))))

(ert-deftest blueprint-test-runtime/add-process-stays-before-next-section ()
  "add-process inserts before the next level-1 section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc"
        (concat "#+TITLE: svc\n\n"
                "* Processi di business\n\n"
                "* Deployment\n\nDeploy config.\n\n"))
      (blueprint-runtime-add-process "svc" "Onboarding")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (let ((pos-proc (string-match "Processo: Onboarding" content))
              (pos-deploy (string-match "\\* Deployment" content)))
          (should pos-proc)
          (should pos-deploy)
          (should (< pos-proc pos-deploy)))))))

(ert-deftest blueprint-test-runtime/add-process-does-not-touch-runtime-behavior ()
  "add-process and add-flow use independent sections and do not collide."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-runtime-add-flow "svc" "Login")
      (blueprint-runtime-add-process "svc" "Onboarding")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/arc42.org" proj))))
        (should (string-match-p "\\* Runtime Behavior" content))
        (should (string-match-p "\\* Processi di business" content))
        (should (string-match-p "Flusso: Login" content))
        (should (string-match-p "Processo: Onboarding" content))))))

(ert-deftest blueprint-test-runtime/add-process-unknown-component ()
  "add-process signals error for unknown component."
  (blueprint-test--with-project
    (should-error (blueprint-runtime-add-process "ghost" "Login") :type 'user-error)))

(provide 'blueprint-test-runtime)
;;; blueprint-test-runtime.el ends here
