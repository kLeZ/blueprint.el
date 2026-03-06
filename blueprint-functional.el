;;; blueprint-functional.el --- Functional spec management for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Interactive commands to incrementally build a component's functional.org.
;; For large or monolithic components the blank template is overwhelming; these
;; commands let the analyst focus on one piece at a time:
;;
;;   `blueprint-functional-add-area'    -- add a level-2 functional area
;;   `blueprint-functional-add-feature' -- add a level-3 feature under an area
;;   `blueprint-functional-add-entity'  -- add a level-2 domain entity
;;
;; Each command opens the file and positions the cursor at the inserted content.
;;
;; Insertion relies on a two-step strategy used throughout the codebase:
;;   1. org-element locates the target heading (`:contents-begin').
;;   2. A regex search finds the next sibling heading (same or higher level).
;;   The new content is inserted just before that sibling (or at EOF).

;;; Code:

(require 'blueprint-core)
(require 'org-element)

;;; --- Internal helpers ---

(defun blueprint--functional-file (component)
  "Return path to functional.org for COMPONENT, or signal an error.
Signals an error if the component does not exist or has no functional.org."
  (let* ((comps (blueprint--components))
         (dir (gethash component comps)))
    (unless dir (user-error "Component %s not found" component))
    (let ((file (expand-file-name "functional.org" dir)))
      (unless (file-exists-p file)
        (user-error "No functional.org for component %s; was it created with the functional template?" component))
      file)))

(defun blueprint--func-slugify (name)
  "Return a slug for NAME: lowercase, non-alphanumeric replaced with hyphens.
Leading and trailing hyphens are stripped."
  (string-trim
   (replace-regexp-in-string
    "-+" "-"
    (replace-regexp-in-string "[^a-z0-9]" "-" (downcase name)))
   "-+" "-+"))

(defun blueprint--func-find-heading (level title)
  "Return `:contents-begin' of heading TITLE at LEVEL in the current buffer.
Uses org-element.  Falls back to `:end' if the heading has no body.
Returns nil if the heading is not found."
  (let (result)
    (org-element-map (org-element-parse-buffer 'headline) 'headline
      (lambda (hl)
        (when (and (= (org-element-property :level hl) level)
                   (string= (org-element-property :raw-value hl) title))
          (setq result (or (org-element-property :contents-begin hl)
                           (org-element-property :end hl)))))
      nil t)
    result))

(defun blueprint--func-goto-section-end (level title)
  "Move point to the insertion position at the end of heading TITLE at LEVEL.
Finds the next heading at LEVEL or above and positions before it, or at EOF.
Returns t when the heading is found, nil otherwise."
  (let ((pos (blueprint--func-find-heading level title)))
    (when pos
      (goto-char pos)
      (let ((next (save-excursion
                    (when (re-search-forward
                           (format "^\\*\\{1,%d\\} " level) nil t)
                      (line-beginning-position)))))
        (goto-char (or next (point-max))))
      t)))

(defun blueprint--func-list-areas (file)
  "Return list of level-2 heading names under `* Aree funzionali' in FILE."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let (areas (in-aree nil))
        (org-element-map (org-element-parse-buffer 'headline) 'headline
          (lambda (hl)
            (let ((lvl (org-element-property :level hl))
                  (raw (org-element-property :raw-value hl)))
              (cond
               ((= lvl 1) (setq in-aree (string= raw "Aree funzionali")))
               ((and in-aree (= lvl 2)) (push raw areas))))))
        (nreverse areas)))))

(defun blueprint--func-list-integrations (file)
  "Return list of level-2 heading names under `* Punti di integrazione' in FILE."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let (integrations (in-punti nil))
        (org-element-map (org-element-parse-buffer 'headline) 'headline
          (lambda (hl)
            (let ((lvl (org-element-property :level hl))
                  (raw (org-element-property :raw-value hl)))
              (cond
               ((= lvl 1) (setq in-punti (string= raw "Punti di integrazione")))
               ((and in-punti (= lvl 2)) (push raw integrations))))))
        (nreverse integrations)))))

;;; --- Public commands ---

;;;###autoload
(defun blueprint-functional-add-area (component area-name)
  "Add a new functional area AREA-NAME to COMPONENT's functional.org.
Inserts a level-2 heading with org anchor and placeholder content under
the `* Aree funzionali' section.  Creates the section if absent."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Area name: ")))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify area-name))
         (anchor (format "%s-area-%s" comp-id slug))
         (content (format "** %s\n<<%s>>\n[DA VALIDARE]\n\nDescrizione dell'area in termini di business.\n\n"
                          area-name anchor))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (blueprint--func-goto-section-end 1 "Aree funzionali")
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Aree funzionali\n\n"))
      (insert content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added area '%s' to %s" area-name component)))

;;;###autoload
(defun blueprint-functional-add-feature (component area feature-name)
  "Add a new feature FEATURE-NAME under AREA in COMPONENT's functional.org.
Inserts a level-3 heading with the standard skeleton: Scopo, Input, Output,
Regole di business, Regole di validazione, Casi limite e eccezioni.
Signals an error if AREA does not exist in the file."
  (interactive
   (let* ((names (hash-table-keys (blueprint--components)))
          (comp (completing-read "Component: " names nil t))
          (dir (gethash comp (blueprint--components)))
          (func-file (when dir (expand-file-name "functional.org" dir)))
          (areas (blueprint--func-list-areas func-file)))
     (unless areas
       (user-error "No areas in %s; add one first with blueprint-functional-add-area"
                   comp))
     (list comp
           (completing-read "Area: " areas nil t)
           (read-string "Feature name: "))))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify feature-name))
         (anchor (format "%s-func-%s" comp-id slug))
         (content (concat
                   (format "*** %s\n<<%s>>\n[DA VALIDARE]\n\n" feature-name anchor)
                   "**** Scopo\n"
                   "Cosa fa questa funzione in termini di business.  Una frase.\n\n"
                   "**** Input\n"
                   "| Nome (business) | Tipo (business) | Vincoli | Provenienza |\n"
                   "|-----------------+-----------------+---------+-------------|\n"
                   "|                 |                 |         |             |\n\n"
                   "**** Output\n"
                   "| Nome (business) | Tipo (business) | Formato | Destinazione |\n"
                   "|-----------------+-----------------+---------+--------------|\n"
                   "|                 |                 |         |              |\n\n"
                   "**** Regole di business\n"
                   "1.\n\n"
                   "**** Regole di validazione\n"
                   "| Condizione | Comportamento / Errore |\n"
                   "|------------+------------------------|\n"
                   "|            |                        |\n\n"
                   "**** Casi limite e eccezioni\n\n"))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (blueprint--func-goto-section-end 2 area)
        (user-error "Area '%s' not found in %s; add it first with blueprint-functional-add-area"
                    area component))
      (insert content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added feature '%s' under area '%s' in %s" feature-name area component)))

;;;###autoload
(defun blueprint-functional-add-entity (component entity-name)
  "Add a new domain entity ENTITY-NAME to COMPONENT's functional.org.
Inserts a level-2 heading with attribute table (including Relazione column)
and a `*** Rappresentazione logica' sub-heading with a PlantUML ER skeleton,
under the `* Entità di dominio' section.  Creates the section if absent.

New entities are always inserted BEFORE `** Diagramma ER generale' (if
present) so that the general diagram remains the last item in the section."
  (interactive
   (list (completing-read "Component: "
                          (hash-table-keys (blueprint--components)) nil t)
         (read-string "Entity name: ")))
  (let* ((file (blueprint--functional-file component))
         (dir (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir)))
         (slug (blueprint--func-slugify entity-name))
         (anchor (format "%s-entity-%s" comp-id slug))
         (er-anchor (format "%s-entity-%s-er" comp-id slug))
         (er-file (format "%s-er-%s.svg" comp-id slug))
         (content (concat
                   (format "** %s\n<<%s>>\n[DA VALIDARE]\n\n" entity-name anchor)
                   "Descrizione.  Attributi principali in termini di business.\n"
                   "La colonna /Relazione/ indica l'entità target per gli attributi "
                   "che sono chiavi esterne (es.: ~→ AltroNome~).\n\n"
                   "| Attributo | Tipo (business) | Vincoli | Relazione | Note |\n"
                   "|-----------+-----------------+---------+-----------+------|\n"
                   "|           |                 |         |           |      |\n\n"
                   (format "*** Rappresentazione logica\n<<%s>>\n\n" er-anchor)
                   "Diagramma ER dell'entità.  Le frecce verso entità esterne "
                   "puntano ai soli identificatori, senza mostrare la struttura "
                   "interna delle entità correlate.\n\n"
                   (format "#+begin_src plantuml :file %s\n" er-file)
                   "@startuml\n"
                   (format "entity \"%s\" as e {\n" entity-name)
                   "  * id : tipo <<PK>>\n"
                   "  --\n"
                   "  attributo : tipo\n"
                   "}\n"
                   "' Entità esterne: solo il bordo, nessun dettaglio interno\n"
                   "' entity \"[Entità correlata]\" as ext #lightgrey {}\n"
                   "' e }o--|| ext : \"descrizione relazione\"\n"
                   "@enduml\n"
                   "#+end_src\n\n"))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      ;; Insert before "** Diagramma ER generale" to keep it as the last item
      (let ((er-general-pos
             (save-excursion
               (goto-char (point-min))
               (when (re-search-forward "^\\*\\* Diagramma ER generale" nil t)
                 (line-beginning-position)))))
        (if er-general-pos
            (goto-char er-general-pos)
          (unless (blueprint--func-goto-section-end 1 "Entità di dominio")
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert "* Entità di dominio\n\n"))))
      (insert content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added entity '%s' to %s" entity-name component)))

;;;###autoload
(defun blueprint-functional-add-integration (component integration-name direction)
  "Add a new integration point INTEGRATION-NAME to COMPONENT's functional.org.
DIRECTION is one of \"IN\", \"OUT\", or \"IN/OUT\".
Inserts a level-2 heading with a metadata table (direction, counterpart,
protocol, authentication, frequency, SLA) and a `*** Formato scambio'
sub-heading with a code block placeholder, under the
`* Punti di integrazione' section.  Creates the section if absent."
  (interactive
   (let* ((names (hash-table-keys (blueprint--components)))
          (comp (completing-read "Component: " names nil t))
          (name (read-string "Integration name: "))
          (dir  (completing-read "Direction: " '("IN" "OUT" "IN/OUT") nil t)))
     (list comp name dir)))
  (let* ((file (blueprint--functional-file component))
         (dir-path (gethash component (blueprint--components)))
         (comp-id (file-name-nondirectory (directory-file-name dir-path)))
         (slug (blueprint--func-slugify integration-name))
         (anchor (format "%s-integ-%s" comp-id slug))
         (fmt-anchor (format "%s-integ-%s-fmt" comp-id slug))
         (content (concat
                   (format "** %s\n<<%s>>\n[DA VALIDARE]\n\n" integration-name anchor)
                   "Descrizione dell'integrazione in termini di business.  Cosa viene\n"
                   "scambiato, perché, e in quale contesto operativo.\n\n"
                   "| Campo          | Valore                                          |\n"
                   "|----------------+-------------------------------------------------|\n"
                   (format "| Direzione      | %-47s |\n" direction)
                   "| Controparte    |                                                 |\n"
                   "| Protocollo     | REST / SOAP / Kafka / gRPC / file / batch / ... |\n"
                   "| Autenticazione | OAuth2 / API key / mTLS / nessuna / ...         |\n"
                   "| Frequenza      | sincrona / asincrona / batch / ...              |\n"
                   "| SLA            |                                                 |\n\n"
                   (format "*** Formato scambio\n<<%s>>\n\n" fmt-anchor)
                   "Struttura del payload o del file scambiato.  Includere un esempio\n"
                   "realistico con tutti i campi obbligatori valorizzati.\n\n"
                   "#+begin_src json\n"
                   "{\n"
                   "  \"attr1\": \"\"\n"
                   "}\n"
                   "#+end_src\n\n"))
         (buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (blueprint--func-goto-section-end 1 "Punti di integrazione")
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "* Punti di integrazione\n\n"))
      (insert content)
      (save-buffer))
    (switch-to-buffer buf)
    (message "Added integration '%s' (%s) to %s" integration-name direction component)))

(provide 'blueprint-functional)
;;; blueprint-functional.el ends here
