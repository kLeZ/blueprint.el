# Blueprint — Piano di implementazione

## Panoramica

Questo file traccia lo stato di implementazione delle feature e raccoglie idee
per lo sviluppo futuro. Le sezioni con ~~testo barrato~~ sono completate.

---

## ~~Fase 1 — Fondamenta e infrastruttura core~~ ✅

### ~~1.1 Metrics caching (`blueprint-core.el`)~~ ✅
- ~~Hash-table cache con invalidazione MD5~~
- ~~`blueprint--invalidate-cache` e `blueprint--cached-metrics`~~

### ~~1.2 Component CRUD completo (`blueprint-core.el`)~~ ✅
- ~~`blueprint-list-components`~~
- ~~`blueprint-rename-component`~~
- ~~`blueprint-delete-component`~~

### ~~1.3 ADR management (`blueprint-adr.el`)~~ ✅
- ~~`blueprint-adr-new` con numerazione automatica~~
- ~~`blueprint-adr-list`~~
- ~~Template `templates/adr.org`~~

### ~~1.4 Linter (`blueprint-lint.el`)~~ ✅
- ~~`blueprint-lint` e `blueprint-lint-component`~~
- ~~Heading check, marker threshold, dangling deps, empty content~~
- ~~**BUGFIX**: `blueprint--lint-component` restituiva lista vuota se il file mancava~~

---

## ~~Fase 2 — Dashboard e navigazione~~ ✅

### ~~2.1 Dashboard buffer (`blueprint-dashboard.el`)~~ ✅
- ~~`blueprint-dashboard` con `tabulated-list-mode`~~
- ~~Header con health score e numero componenti~~

### ~~2.2 Focus mode~~ ✅
- ~~`blueprint-focus` — filtra componenti con marker aperti~~

### ~~2.3 SVG dashboard~~ ✅
- ~~`blueprint-dashboard-svg` — Graphviz con colorazione risk-based~~

---

## ~~Fase 3 — Gestione contenuti e sync~~ ✅

### ~~3.1 Open questions — AST-based (`blueprint-questions.el`)~~ ✅
- ~~`blueprint-add-question` via `org-element`~~
- ~~`blueprint-list-questions`~~

### ~~3.2 Glossary management (`blueprint-glossary.el`)~~ ✅
- ~~`blueprint-glossary-add`, `blueprint-glossary-list`, `blueprint-glossary-lookup`~~

### ~~3.3 Reference tracking (`blueprint-references.el`)~~ ✅
- ~~`blueprint-reference-add`, `blueprint-reference-list`~~

### ~~3.4 Master file sync (`blueprint-sync.el`)~~ ✅
- ~~`blueprint-sync` con marker `@@blueprint-sync-start@@` / `@@blueprint-sync-end@@`~~

### ~~3.5 Ripgrep search (`blueprint-search.el`)~~ ✅
- ~~`blueprint-search`, preset per QUESTION/TBD/FIXME~~

---

## ~~Fase 4 — Export e automazione~~ ✅

### ~~4.1 Org-native export (`blueprint-export.el`)~~ ✅
- ~~PDF, HTML, DOCX (con ox-pandoc)~~

### ~~4.2 Async tangle/export (`blueprint-async.el`)~~ ✅
- ~~`blueprint-async-export`, `blueprint-async-tangle` via `make-thread`~~

### ~~4.3 Auto-tangle on save~~ ✅
- ~~`blueprint-auto-tangle-mode` minor mode~~

### ~~4.4 Watch mode~~ ✅
- ~~`blueprint-watch-mode` con auto-sync e auto-C4~~

---

## ~~Fase 5 — Dependency graph avanzato~~ ✅

### ~~5.1 Dependency graph (`blueprint-graph.el`)~~ ✅
- ~~PlantUML e Graphviz, colorazione health-based~~

---

## ~~Fase 6 — UX e onboarding~~ ✅

### ~~6.1 Component skeleton wizard (`blueprint-wizard.el`)~~ ✅
- ~~`blueprint-wizard-component` con pre-compilazione~~

### ~~6.2 Wizard onboarding~~ ✅
- ~~`blueprint-wizard-init`~~

### ~~6.3 Quick capture (`blueprint-capture.el`)~~ ✅
- ~~Template org-capture per note, domande, glossario~~

### ~~6.4 Daily workflow command (`blueprint-daily.el`)~~ ✅
- ~~`blueprint-daily` — sequenza triage giornaliero~~

---

## ~~Fase 7 — Intelligence e integrazione esterna~~ ✅

### ~~7.1 Rule-based risk suggestions (`blueprint-risks.el`)~~ ✅
- ~~Pattern matching deterministico + check strutturali~~

### ~~7.2 AI-assisted snippets — Ollama (`blueprint-ai.el`)~~ ✅
- ~~`blueprint-ai-expand`, `blueprint-ai-suggest-risks`, `blueprint-ai-boilerplate`~~

### ~~7.3 Prompt guardrails~~ ✅
- ~~Context clamping + sanitizzazione email/IP/password~~

### ~~7.4 Org-roam integration (`blueprint-roam.el`)~~ ✅
- ~~Soft dependency con `require ... nil t`~~

### ~~7.5 CI/headless mode (`blueprint-ci.el`)~~ ✅
- ~~`blueprint-ci-lint`, `blueprint-ci-export`, `blueprint-ci-validate`~~

---

## ~~Infrastruttura test e licenza~~ ✅

- ~~Suite ERT in `test/` a più livelli (unit, integration, end-to-end)~~
- ~~CI GitHub Actions (`test.yml`) che esegue tutti i test~~
- ~~Licenza MIT (`LICENSE`)~~
- ~~`AGENTS.md` per agenti AI~~
- ~~Fix bug `blueprint--lint-component` (file mancante silenzioso)~~

---

## Fase 8 — Qualità e robustezza (TODO)

### 8.1 Fix noti e tech debt

- [ ] `blueprint-questions.el`: `blueprint--find-heading` non gestisce heading
  con sottotitoli (`:CUSTOM_ID:`, etc.) — usare `:raw-value` è corretto ma
  verificare edge case con heading nested
- [ ] `blueprint-sync.el`: primo sync aggiunge newline extra prima del contenuto
  (cosmetic, non funzionale)
- [ ] `blueprint-wizard.el`: `blueprint-wizard-component` scrive `#+BLUEPRINT_OWNER:`
  e `#+BLUEPRINT_TECH:` ma nessun altro modulo li legge — documentare o
  consumarli da qualche parte
- [ ] `blueprint-rename-component`: dopo rename, la cache non viene invalidata
  per i file dei componenti che hanno aggiornato le dipendenze
- [ ] `blueprint-export.el`: `blueprint--master-or-error` blocca l'utente se
  non ha mai eseguito `blueprint-sync` — aggiungere suggerimento automatico

### 8.2 Miglioramenti ai test

- [ ] Aggiungere test per `blueprint-dashboard.el` (buffer entries, focus mode)
- [ ] Aggiungere test per `blueprint-migrate.el` (diff e migrazione non-distruttiva)
- [ ] Aggiungere test per `blueprint-watch.el` (hook install/remove)
- [ ] Test negativi più sistematici (input invalido, file corrotti)

---

## Fase 9 — Nuove feature (idee)

### 9.1 Changelog automatico

Generare un file `CHANGELOG.org` a partire dai messaggi dei commit git e
dagli ADR. Comando: `blueprint-changelog-generate`.

### 9.2 Status tracking per componenti

Aggiungere keyword `#+BLUEPRINT_STATUS: draft|active|deprecated|archived`
interpretata dalla dashboard con icone colorate. Il linter potrebbe avvisare
se un componente `active` ha FIXMEs o dipende da uno `deprecated`.

### 9.3 Metriche trend nel tempo

Registrare lo stato delle metriche (score, conteggi) in `.blueprint/metrics-history.org`
ad ogni sync, in modo da mostrare un grafico dell'evoluzione del progetto.

### 9.4 Esportazione JSON/YAML per CI

Aggiungere `blueprint-ci-export-json` che produce un file `blueprint-report.json`
con health score, componenti, dipendenze e warning — utile per integrazione
con tool di CI che non supportano Emacs.

### 9.5 Template "enterprise" con multi-livello

Supporto per template `arc42-enterprise.org` con sezioni aggiuntive
(enterprise context, stakeholder map, compliance) per engagement più grandi.
L'assessment framework in `assessment-framework/` contiene già la base.

### 9.6 Integrazione con org-agenda

Convertire le QUESTION e FIXME aperte in task org-agenda con scadenza,
in modo da poter fare triage dal buffer agenda standard di Emacs.

### 9.7 Diff tra versioni di componente

Usare git per mostrare la diff delle modifiche ai file arc42.org con
contesto semantico (quale heading è cambiato, quante domande sono state
risolte). Comando: `blueprint-component-diff`.

### 9.8 Ricerca semantica con org-roam-db

Se org-roam è disponibile, sfruttare il suo database SQLite per ricerche
semantiche tra componenti (componenti simili, cluster di dipendenze, ecc.).

### 9.9 Blueprint per monorepo

Supporto per progetti con più sotto-sistemi: `.blueprint/systems/` con una
directory per sistema, ciascuna con la propria struttura components/adr.
Il dashboard mostrerebbe una vista aggregata multi-sistema.

### 9.10 Live preview nella sidebar

Minor mode che apre un buffer laterale con l'anteprima SVG del grafico
delle dipendenze, aggiornata in tempo reale al salvataggio dei file.
