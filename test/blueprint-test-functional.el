;;; blueprint-test-functional.el --- Tests for blueprint-functional.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the incremental functional spec authoring commands:
;;   blueprint-functional-add-area, -add-feature, -add-entity, -add-integration.
;; Also covers the private helpers used by those commands.
;;
;; NOTE: functions that call `find-file-noselect' followed by `switch-to-buffer'
;; change the current buffer and therefore `default-directory' (which is
;; buffer-local).  Always capture the project root in a local `proj' variable
;; BEFORE calling such functions.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-functional)

;;; --- Test helper ---

(defun blueprint-test--write-functional (component &optional content)
  "Create functional.org for COMPONENT with optional CONTENT.
Requires `default-directory' to be inside a Blueprint project."
  (let* ((dir (expand-file-name
               (concat ".blueprint/components/" component)
               default-directory))
         (file (expand-file-name "functional.org" dir))
         (body (or content
                   (concat "#+TITLE: " component " -- Specifiche funzionali\n\n"
                           "* Aree funzionali\n\n"
                           "* Entità di dominio\n\n"
                           "* Punti di integrazione\n\n"))))
    (make-directory dir t)
    (with-temp-file file (insert body))
    file))

;;; --- blueprint--func-slugify ---

(ert-deftest blueprint-test-functional/slugify-lowercase ()
  "Slugify converts to lowercase."
  (should (string= "order-service" (blueprint--func-slugify "Order Service"))))

(ert-deftest blueprint-test-functional/slugify-special-chars ()
  "Slugify replaces non-alphanumeric with hyphens and strips trailing ones."
  (should (string= "order-api-v2" (blueprint--func-slugify "Order API v2"))))

(ert-deftest blueprint-test-functional/slugify-collapses-hyphens ()
  "Slugify collapses consecutive hyphens to one."
  (should (string= "a-b" (blueprint--func-slugify "a  b"))))

(ert-deftest blueprint-test-functional/slugify-already-slug ()
  "Slugify is idempotent on already-valid slugs."
  (should (string= "my-service" (blueprint--func-slugify "my-service"))))

(ert-deftest blueprint-test-functional/slugify-strips-trailing-hyphens ()
  "Slugify strips leading and trailing hyphens."
  (should (string= "checkout-v2" (blueprint--func-slugify "Checkout (v2)"))))

;;; --- blueprint--func-list-areas ---

(ert-deftest blueprint-test-functional/list-areas-nil-file ()
  "list-areas returns nil when file is nil."
  (should (null (blueprint--func-list-areas nil))))

(ert-deftest blueprint-test-functional/list-areas-missing-file ()
  "list-areas returns nil when file does not exist."
  (should (null (blueprint--func-list-areas "/tmp/blueprint-nonexistent-9999.org"))))

(ert-deftest blueprint-test-functional/list-areas-empty-section ()
  "list-areas returns nil when Aree funzionali section has no areas."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-functional "comp"
               "#+TITLE: comp\n\n* Aree funzionali\n\n")))
      (should (null (blueprint--func-list-areas f))))))

(ert-deftest blueprint-test-functional/list-areas-finds-areas ()
  "list-areas returns level-2 headings under Aree funzionali only."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-functional "comp"
               (concat "#+TITLE: comp\n\n"
                       "* Aree funzionali\n\n"
                       "** Gestione ordini\n\nContent.\n\n"
                       "** Pagamenti\n\nContent.\n\n"
                       "* Entità di dominio\n\n"
                       "** Sotto-voce estranea\n\n"))))
      (let ((areas (blueprint--func-list-areas f)))
        (should (member "Gestione ordini" areas))
        (should (member "Pagamenti" areas))
        (should-not (member "Sotto-voce estranea" areas))))))

(ert-deftest blueprint-test-functional/list-areas-order ()
  "list-areas preserves document order."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-functional "comp"
               (concat "#+TITLE: comp\n\n"
                       "* Aree funzionali\n\n"
                       "** Alpha\n\nContent.\n\n"
                       "** Beta\n\nContent.\n\n"
                       "** Gamma\n\nContent.\n\n"))))
      (let ((areas (blueprint--func-list-areas f)))
        (should (equal '("Alpha" "Beta" "Gamma") areas))))))

;;; --- blueprint--func-list-integrations ---

(ert-deftest blueprint-test-functional/list-integrations-nil ()
  "list-integrations returns nil when file is nil."
  (should (null (blueprint--func-list-integrations nil))))

(ert-deftest blueprint-test-functional/list-integrations-empty ()
  "list-integrations returns nil when section has no entries."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-functional "comp"
               "#+TITLE: comp\n\n* Punti di integrazione\n\n")))
      (should (null (blueprint--func-list-integrations f))))))

(ert-deftest blueprint-test-functional/list-integrations-finds-entries ()
  "list-integrations returns level-2 headings under Punti di integrazione only."
  (blueprint-test--with-project
    (let ((f (blueprint-test--write-functional "comp"
               (concat "#+TITLE: comp\n\n"
                       "* Aree funzionali\n\n"
                       "** Non integration\n\n"
                       "* Punti di integrazione\n\n"
                       "** API Pagamenti\n\nContent.\n\n"
                       "** CRM sync\n\nContent.\n\n"))))
      (let ((integrations (blueprint--func-list-integrations f)))
        (should (member "API Pagamenti" integrations))
        (should (member "CRM sync" integrations))
        (should-not (member "Non integration" integrations))))))

;;; --- blueprint--functional-file ---

(ert-deftest blueprint-test-functional/file-component-not-found ()
  "blueprint--functional-file signals error when component is unknown."
  (blueprint-test--with-project
    (should-error (blueprint--functional-file "ghost") :type 'user-error)))

(ert-deftest blueprint-test-functional/file-no-functional-org ()
  "blueprint--functional-file signals error when functional.org is absent."
  (blueprint-test--with-project
    (blueprint-test--write-component "only-arc42")
    (should-error (blueprint--functional-file "only-arc42") :type 'user-error)))

(ert-deftest blueprint-test-functional/file-returns-path ()
  "blueprint--functional-file returns the path when functional.org exists."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-functional "svc")
    (let ((path (blueprint--functional-file "svc")))
      (should (stringp path))
      (should (file-exists-p path))
      (should (string-match-p "functional\\.org$" path)))))

;;; --- blueprint-functional-add-area ---

(ert-deftest blueprint-test-functional/add-area-creates-section ()
  "add-area creates Aree funzionali section when absent."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc" "#+TITLE: svc\n\n")
      (blueprint-functional-add-area "svc" "Gestione ordini")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\* Aree funzionali" content))
        (should (string-match-p "\\*\\* Gestione ordini" content))))))

(ert-deftest blueprint-test-functional/add-area-under-existing-section ()
  "add-area appends under an existing Aree funzionali section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Pagamenti")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\*\\* Pagamenti" content))))))

(ert-deftest blueprint-test-functional/add-area-multiple-areas ()
  "Multiple add-area calls accumulate areas."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Area Alfa")
      (blueprint-functional-add-area "svc" "Area Beta")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "Area Alfa" content))
        (should (string-match-p "Area Beta" content))))))

(ert-deftest blueprint-test-functional/add-area-has-anchor ()
  "add-area inserts an org anchor based on component-id and area slug."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Gestione Ordini")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "<<svc-area-gestione-ordini>>" content))))))

(ert-deftest blueprint-test-functional/add-area-has-to-validate ()
  "add-area inserts the [TO VALIDATE] marker."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Reporting")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\[TO VALIDATE\\]" content))))))

(ert-deftest blueprint-test-functional/add-area-unknown-component ()
  "add-area signals error for unknown component."
  (blueprint-test--with-project
    (should-error (blueprint-functional-add-area "ghost" "Area") :type 'user-error)))

;;; --- blueprint-functional-add-feature ---

(ert-deftest blueprint-test-functional/add-feature-inserts-under-area ()
  "add-feature inserts a level-3 heading under the specified area."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Gestione ordini")
      (blueprint-functional-add-feature "svc" "Gestione ordini" "Crea ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\*\\*\\* Crea ordine" content))))))

(ert-deftest blueprint-test-functional/add-feature-skeleton-has-all-sections ()
  "add-feature inserts skeleton with all required sub-headings."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Ordini")
      (blueprint-functional-add-feature "svc" "Ordini" "Crea ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\*\\*\\*\\* Scopo" content))
        (should (string-match-p "\\*\\*\\*\\* Input" content))
        (should (string-match-p "\\*\\*\\*\\* Output" content))
        (should (string-match-p "Regole di business" content))
        (should (string-match-p "Regole di validazione" content))
        (should (string-match-p "Casi limite" content))))))

(ert-deftest blueprint-test-functional/add-feature-multiple-features ()
  "Multiple features can be added under the same area."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Ordini")
      (blueprint-functional-add-feature "svc" "Ordini" "Crea ordine")
      (blueprint-functional-add-feature "svc" "Ordini" "Annulla ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "Crea ordine" content))
        (should (string-match-p "Annulla ordine" content))))))

(ert-deftest blueprint-test-functional/add-feature-area-not-found ()
  "add-feature signals error when the area does not exist."
  (blueprint-test--with-project
    (blueprint-test--write-component "svc")
    (blueprint-test--write-functional "svc")
    (should-error
     (blueprint-functional-add-feature "svc" "Area Inesistente" "Feature")
     :type 'user-error)))

(ert-deftest blueprint-test-functional/add-feature-stays-in-area ()
  "Feature is inserted inside the correct area, not after a sibling area."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-area "svc" "Area A")
      (blueprint-functional-add-area "svc" "Area B")
      (blueprint-functional-add-feature "svc" "Area A" "Feature di A")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (let ((pos-feature (string-match "Feature di A" content))
              (pos-area-b (string-match "\\*\\* Area B" content)))
          (should pos-feature)
          (should pos-area-b)
          (should (< pos-feature pos-area-b)))))))

;;; --- blueprint-functional-add-entity ---

(ert-deftest blueprint-test-functional/add-entity-creates-section ()
  "add-entity creates Entità di dominio section when absent."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc" "#+TITLE: svc\n\n")
      (blueprint-functional-add-entity "svc" "Ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\* Entità di dominio" content))
        (should (string-match-p "\\*\\* Ordine" content))))))

(ert-deftest blueprint-test-functional/add-entity-has-attribute-table ()
  "add-entity inserts an attribute table with the Relazione column."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-entity "svc" "Ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "Attributo" content))
        (should (string-match-p "Relazione" content))))))

(ert-deftest blueprint-test-functional/add-entity-has-plantuml-block ()
  "add-entity inserts a PlantUML ER diagram block."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-entity "svc" "Prodotto")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "begin_src plantuml" content))
        (should (string-match-p "@startuml" content))
        (should (string-match-p "entity \"Prodotto\"" content))))))

(ert-deftest blueprint-test-functional/add-entity-before-er-generale ()
  "add-entity inserts before ** Diagramma ER generale when present."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc"
        (concat "#+TITLE: svc\n\n"
                "* Entità di dominio\n\n"
                "** Diagramma ER generale\n\nDiagramma generale.\n\n"))
      (blueprint-functional-add-entity "svc" "Ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (let ((pos-ordine (string-match "\\*\\* Ordine" content))
              (pos-er (string-match "Diagramma ER generale" content)))
          (should pos-ordine)
          (should pos-er)
          (should (< pos-ordine pos-er)))))))

(ert-deftest blueprint-test-functional/add-entity-multiple-entities ()
  "Multiple entities accumulate in the section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-entity "svc" "Ordine")
      (blueprint-functional-add-entity "svc" "Cliente")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\*\\* Ordine" content))
        (should (string-match-p "\\*\\* Cliente" content))))))

(ert-deftest blueprint-test-functional/add-entity-has-er-anchor ()
  "add-entity creates an org anchor for the ER sub-section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-entity "svc" "Ordine")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "svc-entity-ordine-er" content))))))

;;; --- blueprint-functional-add-integration ---

(ert-deftest blueprint-test-functional/add-integration-creates-section ()
  "add-integration creates Punti di integrazione section when absent."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc" "#+TITLE: svc\n\n")
      (blueprint-functional-add-integration "svc" "API Pagamenti" "OUT")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "\\* Punti di integrazione" content))
        (should (string-match-p "\\*\\* API Pagamenti" content))))))

(ert-deftest blueprint-test-functional/add-integration-direction-in-table ()
  "add-integration includes the direction in the metadata table."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-integration "svc" "CRM" "IN")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "Direzione" content))
        (should (string-match-p "IN" content))))))

(ert-deftest blueprint-test-functional/add-integration-formato-scambio ()
  "add-integration inserts a *** Formato scambio sub-section with JSON block."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-integration "svc" "Kafka events" "OUT")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "Formato scambio" content))
        (should (string-match-p "begin_src json" content))))))

(ert-deftest blueprint-test-functional/add-integration-multiple ()
  "Multiple integrations accumulate in the section."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-integration "svc" "API Pagamenti" "OUT")
      (blueprint-functional-add-integration "svc" "CRM sync" "IN")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "API Pagamenti" content))
        (should (string-match-p "CRM sync" content))))))

(ert-deftest blueprint-test-functional/add-integration-direction-inout ()
  "add-integration supports IN/OUT direction."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-integration "svc" "Webhook" "IN/OUT")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "IN/OUT" content))))))

(ert-deftest blueprint-test-functional/add-integration-anchor ()
  "add-integration creates org anchors for integration and format sections."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "svc")
      (blueprint-test--write-functional "svc")
      (blueprint-functional-add-integration "svc" "API Pagamenti" "OUT")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/svc/functional.org" proj))))
        (should (string-match-p "svc-integ-api-pagamenti" content))
        (should (string-match-p "svc-integ-api-pagamenti-fmt" content))))))

;;; --- Integration: combined workflow ---

(ert-deftest blueprint-test-functional/combined-workflow ()
  "Full workflow: area, feature, entity and integration can all coexist."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--write-component "shop")
      (blueprint-test--write-functional "shop")
      (blueprint-functional-add-area "shop" "Catalogo prodotti")
      (blueprint-functional-add-feature "shop" "Catalogo prodotti" "Cerca prodotto")
      (blueprint-functional-add-entity "shop" "Prodotto")
      (blueprint-functional-add-integration "shop" "Inventory API" "IN")
      (let ((content (blueprint-test--read-file
                      (expand-file-name ".blueprint/components/shop/functional.org" proj))))
        (should (string-match-p "Catalogo prodotti" content))
        (should (string-match-p "Cerca prodotto" content))
        (should (string-match-p "\\*\\* Prodotto" content))
        (should (string-match-p "Inventory API" content))))))

(provide 'blueprint-test-functional)
;;; blueprint-test-functional.el ends here
