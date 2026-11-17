;;; blueprint-ai.el --- AI-assisted snippets via Ollama for Blueprint  -*- lexical-binding:t; -*-
;; SPDX-License-Identifier: MIT

;; Author: kLeZ <julius8774@gmail.com>
;; URL: https://github.com/kLeZ/blueprint.el

;;; Commentary:

;; Optional integration with Ollama (local LLM) for section expansion,
;; risk suggestion, and boilerplate generation.  Fully offline — no data
;; leaves the machine.  Falls back to rule-based suggestions when Ollama
;; is not running.  Includes prompt guardrails: context clamping and
;; sanitization.

;;; Code:

(require 'blueprint-core)
(require 'json)
(require 'url)

(declare-function blueprint-suggest-risks "blueprint-risks" (component))

(defcustom blueprint-ai-model "llama3"
  "Ollama model to use for AI-assisted snippets."
  :type 'string
  :group 'blueprint)

(defcustom blueprint-ai-endpoint "http://localhost:11434"
  "Ollama API endpoint URL."
  :type 'string
  :group 'blueprint)

(defcustom blueprint-ai-max-context 4000
  "Maximum number of characters to send as context to the LLM."
  :type 'integer
  :group 'blueprint)

;;; --- Prompt guardrails ---

(defun blueprint--ai-sanitize (text)
  "Remove potentially sensitive patterns from TEXT.
Strips email addresses, IP addresses, and password-like patterns."
  (let ((result text))
    (setq result (replace-regexp-in-string
                  "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]\\{2,\\}"
                  "[EMAIL]" result))
    (setq result (replace-regexp-in-string
                  "\\b[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\b"
                  "[IP]" result))
    (setq result (replace-regexp-in-string
                  "\\b\\(password\\|secret\\|token\\|api.key\\)\\s-*[:=]\\s-*\\S-+"
                  "\\1=[REDACTED]" result t))
    result))

(defun blueprint--ai-clamp (text)
  "Clamp TEXT to `blueprint-ai-max-context' characters."
  (if (> (length text) blueprint-ai-max-context)
      (substring text 0 blueprint-ai-max-context)
    text))

(defun blueprint--ai-prepare-context (text)
  "Sanitize and clamp TEXT for use as LLM context."
  (blueprint--ai-clamp (blueprint--ai-sanitize text)))

;;; --- Ollama API ---

(defun blueprint--ai-available-p ()
  "Return non-nil if Ollama is reachable."
  (condition-case nil
      (let ((url-request-method "GET")
            (url-show-status nil))
        (with-current-buffer
            (url-retrieve-synchronously
             (format "%s/api/tags" blueprint-ai-endpoint) t nil 3)
          (prog1 t (kill-buffer))))
    (error nil)))

(defun blueprint--ai-generate (prompt context)
  "Send PROMPT with CONTEXT to Ollama and return the response text."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (safe-context (blueprint--ai-prepare-context context))
         (payload (json-encode
                   `((model . ,blueprint-ai-model)
                     (prompt . ,(format "%s\n\nContext:\n%s" prompt safe-context))
                     (stream . :json-false))))
         (url-request-data (encode-coding-string payload 'utf-8))
         (buf (url-retrieve-synchronously
               (format "%s/api/generate" blueprint-ai-endpoint) t nil 120)))
    (when buf
      (with-current-buffer buf
        (goto-char (point-min))
        (re-search-forward "\n\n" nil t)
        (let* ((json-object-type 'alist)
               (data (json-read)))
          (kill-buffer)
          (alist-get 'response data))))))

;;;###autoload
(defun blueprint-ai-expand ()
  "Expand the current section using AI.
Uses the content around point as context and asks the LLM to expand it."
  (interactive)
  (unless (blueprint--ai-available-p)
    (user-error "Ollama is not running at %s" blueprint-ai-endpoint))
  (let* ((context (buffer-substring-no-properties
                   (max (point-min) (- (point) 2000))
                   (min (point-max) (+ (point) 2000))))
         (prompt "You are an architecture documentation assistant. Expand the following section with detailed, professional content. Keep it concise and relevant. Output only the expanded text, no explanations.")
         (result (blueprint--ai-generate prompt context)))
    (if result
        (progn
          (end-of-line)
          (insert "\n" result))
      (message "No response from Ollama"))))

;;;###autoload
(defun blueprint-ai-suggest-risks ()
  "Suggest architectural risks using AI.
Falls back to rule-based suggestions if Ollama is not available."
  (interactive)
  (if (blueprint--ai-available-p)
      (let* ((context (buffer-substring-no-properties (point-min)
                                                      (min (point-max) 8000)))
             (prompt "You are a software architecture reviewer. Analyze the following component documentation and list potential architectural risks. Format each risk as a bullet point with severity (HIGH/MEDIUM/LOW). Be specific and actionable.")
             (result (blueprint--ai-generate prompt context)))
        (if result
            (with-current-buffer (get-buffer-create "*Blueprint AI Risks*")
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "AI Risk Suggestions\n\n" result))
              (goto-char (point-min))
              (special-mode)
              (switch-to-buffer (current-buffer)))
          (message "No response from Ollama")))
    ;; Fallback to rule-based
    (require 'blueprint-risks)
    (message "Ollama not available, falling back to rule-based suggestions")
    (let ((comps (blueprint--components))
          (id nil))
      ;; Try to detect component from current buffer
      (when buffer-file-name
        (maphash (lambda (cid dir)
                   (when (string-prefix-p dir buffer-file-name)
                     (setq id cid)))
                 comps))
      (if id
          (blueprint-suggest-risks id)
        (call-interactively #'blueprint-suggest-risks)))))

;;;###autoload
(defun blueprint-ai-boilerplate ()
  "Generate boilerplate content for empty sections using AI."
  (interactive)
  (unless (blueprint--ai-available-p)
    (user-error "Ollama is not running at %s" blueprint-ai-endpoint))
  (let* ((heading (save-excursion
                    (org-back-to-heading t)
                    (org-get-heading t t t t)))
         (component-name (save-excursion
                           (goto-char (point-min))
                           (when (re-search-forward "^#\\+TITLE:\\s-*\\(.*\\)" nil t)
                             (match-string 1))))
         (prompt (format "You are an architecture documentation assistant. Generate professional boilerplate content for the \"%s\" section of a software component called \"%s\". Use Org mode formatting. Keep it concise (3-5 paragraphs)."
                         heading (or component-name "unknown")))
         (result (blueprint--ai-generate prompt "")))
    (if result
        (progn
          (org-end-of-subtree)
          (insert "\n" result "\n"))
      (message "No response from Ollama"))))

(provide 'blueprint-ai)
;;; blueprint-ai.el ends here
