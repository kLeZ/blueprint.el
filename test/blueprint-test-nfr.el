;;; blueprint-test-nfr.el --- Tests for blueprint-nfr.el  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the NFR management module: quality scenarios, constraints,
;; and risk register entries.
;;
;; Each test that exercises file I/O calls `blueprint-init' inside
;; `blueprint-test--with-project' to ensure nfr/ files exist.
;; `default-directory' is captured in `proj' before any command that
;; calls `find-file', since those change the current buffer.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-nfr)

;;; --- Helpers ---

(defun blueprint-test--setup-nfr ()
  "Initialize project and create minimal NFR files in the current test project."
  (blueprint-init "test-project" "test-author"))

;;; --- blueprint--nfr-risk-level ---

(ert-deftest blueprint-test-nfr-risk-level/critico ()
  "Alta + Alto → Critico."
  (should (equal "Critico" (blueprint--nfr-risk-level "Alta" "Alto"))))

(ert-deftest blueprint-test-nfr-risk-level/alto-1 ()
  "Alta + Medio → Alto."
  (should (equal "Alto" (blueprint--nfr-risk-level "Alta" "Medio"))))

(ert-deftest blueprint-test-nfr-risk-level/alto-2 ()
  "Media + Alto → Alto."
  (should (equal "Alto" (blueprint--nfr-risk-level "Media" "Alto"))))

(ert-deftest blueprint-test-nfr-risk-level/medio ()
  "Media + Medio → Medio."
  (should (equal "Medio" (blueprint--nfr-risk-level "Media" "Medio"))))

(ert-deftest blueprint-test-nfr-risk-level/basso ()
  "Bassa + Basso → Basso."
  (should (equal "Basso" (blueprint--nfr-risk-level "Bassa" "Basso"))))

;;; --- blueprint--nfr-next-risk-id ---

(ert-deftest blueprint-test-nfr-risk-id/no-file ()
  "Returns R-001 when nfr/risks.org does not exist."
  (blueprint-test--with-project
    (should (equal "R-001" (blueprint--nfr-next-risk-id)))))

(ert-deftest blueprint-test-nfr-risk-id/empty-table ()
  "Returns R-001 when risks.org has no R-NNN entries."
  (blueprint-test--with-project
    (let ((file (expand-file-name "nfr/risks.org" default-directory)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert "* Registro dei rischi\n| ID | Rischio |\n|-\n"))
      (should (equal "R-001" (blueprint--nfr-next-risk-id))))))

(ert-deftest blueprint-test-nfr-risk-id/sequential ()
  "Increments past the highest existing ID."
  (blueprint-test--with-project
    (blueprint-test--setup-nfr)
    (let ((file (expand-file-name "nfr/risks.org" default-directory)))
      (with-temp-file file
        (insert "* Registro dei rischi\n| ID | Rischio |\n|-\n| R-003 | foo |\n| R-001 | bar |\n")))
    (should (equal "R-004" (blueprint--nfr-next-risk-id)))))

;;; --- blueprint-nfr-add-quality-scenario ---

(ert-deftest blueprint-test-nfr-quality/creates-heading ()
  "blueprint-nfr-add-quality-scenario appends a level-2 heading."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-quality-scenario "Performance" "Latenza API sotto carico")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/quality-scenarios.org" proj))))
        (should (string-match-p "\\*\\* Latenza API sotto carico" content))))))

(ert-deftest blueprint-test-nfr-quality/has-attribute ()
  "The new heading contains the quality attribute."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-quality-scenario "Sicurezza" "Autenticazione JWT")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/quality-scenarios.org" proj))))
        (should (string-match-p "Attributo di qualità.*Sicurezza" content))))))

(ert-deftest blueprint-test-nfr-quality/has-skeleton-fields ()
  "The new scenario contains all required skeleton fields."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-quality-scenario "Affidabilità" "Uptime produzione")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/quality-scenarios.org" proj))))
        (should (string-match-p "Contesto" content))
        (should (string-match-p "Stimolo" content))
        (should (string-match-p "Risposta attesa" content))
        (should (string-match-p "Misura" content))
        (should (string-match-p "Priorità" content))
        (should (string-match-p "Fonte" content))))))

(ert-deftest blueprint-test-nfr-quality/multiple-scenarios ()
  "Multiple scenarios accumulate in the same file."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-quality-scenario "Performance" "Scenario A")
      (blueprint-nfr-add-quality-scenario "Scalabilità" "Scenario B")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/quality-scenarios.org" proj))))
        (should (string-match-p "Scenario A" content))
        (should (string-match-p "Scenario B" content))))))

;;; --- blueprint-nfr-add-constraint ---

(ert-deftest blueprint-test-nfr-constraint/tecnico ()
  "Adds a technical constraint row to nfr/constraints.org."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-constraint "tecnico" "JVM 17 minimo")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/constraints.org" proj))))
        (should (string-match-p "JVM 17 minimo" content))))))

(ert-deftest blueprint-test-nfr-constraint/organizzativo ()
  "Adds an organisational constraint row."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-constraint "organizzativo" "Team di 2 persone")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/constraints.org" proj))))
        (should (string-match-p "Team di 2 persone" content))))))

(ert-deftest blueprint-test-nfr-constraint/normativo ()
  "Adds a regulatory constraint row."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-constraint "normativo" "GDPR Art. 25")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/constraints.org" proj))))
        (should (string-match-p "GDPR Art. 25" content))))))

(ert-deftest blueprint-test-nfr-constraint/multiple-types ()
  "Constraints of different types accumulate in the same file."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-constraint "tecnico" "Vincolo tecnico")
      (blueprint-nfr-add-constraint "normativo" "Vincolo normativo")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/constraints.org" proj))))
        (should (string-match-p "Vincolo tecnico" content))
        (should (string-match-p "Vincolo normativo" content))))))

;;; --- blueprint-nfr-add-risk ---

(ert-deftest blueprint-test-nfr-risk/creates-row ()
  "blueprint-nfr-add-risk appends a table row to nfr/risks.org."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Nessun backup strategy" "database" "Alta" "Alto")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "Nessun backup strategy" content))))))

(ert-deftest blueprint-test-nfr-risk/auto-numbering ()
  "First risk gets ID R-001."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Primo rischio" "" "Media" "Medio")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "R-001" content))))))

(ert-deftest blueprint-test-nfr-risk/sequential-ids ()
  "Multiple risks get sequential IDs."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Rischio A" "" "Alta" "Alto")
      (blueprint-nfr-add-risk "Rischio B" "comp" "Media" "Medio")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "R-001" content))
        (should (string-match-p "R-002" content))))))

(ert-deftest blueprint-test-nfr-risk/level-calculated ()
  "Risk level is calculated from probability × impact."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Rischio critico" "" "Alta" "Alto")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "Critico" content))))))

(ert-deftest blueprint-test-nfr-risk/crosscutting-component ()
  "Blank component is replaced with (trasversale)."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Rischio trasversale" "" "Bassa" "Basso")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "trasversale" content))))))

(ert-deftest blueprint-test-nfr-risk/has-component-name ()
  "Specified component name appears in the row."
  (blueprint-test--with-project
    (let ((proj default-directory))
      (blueprint-test--setup-nfr)
      (blueprint-nfr-add-risk "Rischio localizzato" "order-service" "Media" "Alto")
      (let ((content (blueprint-test--read-file
                      (expand-file-name "nfr/risks.org" proj))))
        (should (string-match-p "order-service" content))))))

(provide 'blueprint-test-nfr)
;;; blueprint-test-nfr.el ends here
