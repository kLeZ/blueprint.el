;;; blueprint-test-ai.el --- Tests for blueprint-ai.el guardrails  -*- lexical-binding:t; -*-

;;; Commentary:

;; Tests for the AI prompt guardrail functions: sanitization and clamping.
;; These tests do not require a running Ollama instance.

;;; Code:

(require 'ert)
(require 'blueprint-test-helpers)
(require 'blueprint-core)
(require 'blueprint-ai)

;;; --- blueprint--ai-sanitize ---

(ert-deftest blueprint-test-ai/sanitize-email ()
  "Email addresses are replaced with [EMAIL]."
  (let ((result (blueprint--ai-sanitize "Contact admin@example.com for details.")))
    (should (string-match-p "\\[EMAIL\\]" result))
    (should-not (string-match-p "admin@example.com" result))))

(ert-deftest blueprint-test-ai/sanitize-multiple-emails ()
  "Multiple email addresses are all replaced."
  (let ((result (blueprint--ai-sanitize "From: a@b.com to c@d.org")))
    (should-not (string-match-p "a@b.com" result))
    (should-not (string-match-p "c@d.org" result))
    (should (= 2 (cl-count-if (lambda (s) (string= s "[EMAIL]"))
                               (split-string result))))))

(ert-deftest blueprint-test-ai/sanitize-ip-address ()
  "IPv4 addresses are replaced with [IP]."
  (let ((result (blueprint--ai-sanitize "Server runs on 192.168.1.100.")))
    (should (string-match-p "\\[IP\\]" result))
    (should-not (string-match-p "192\\.168\\.1\\.100" result))))

(ert-deftest blueprint-test-ai/sanitize-password-pattern ()
  "password=VALUE patterns are sanitized."
  (let ((result (blueprint--ai-sanitize "password: mysecret123")))
    (should (string-match-p "REDACTED" result))
    (should-not (string-match-p "mysecret123" result))))

(ert-deftest blueprint-test-ai/sanitize-token-pattern ()
  "token=VALUE patterns are sanitized."
  (let ((result (blueprint--ai-sanitize "token=abc123xyz")))
    (should (string-match-p "REDACTED" result))
    (should-not (string-match-p "abc123xyz" result))))

(ert-deftest blueprint-test-ai/sanitize-clean-text ()
  "Clean text without sensitive data passes through unchanged."
  (let ((text "This is a description of the API gateway component."))
    (should (string= text (blueprint--ai-sanitize text)))))

(ert-deftest blueprint-test-ai/sanitize-preserves-structure ()
  "Sanitization preserves text structure around replaced patterns."
  (let ((result (blueprint--ai-sanitize "Before admin@test.com after")))
    (should (string-match-p "Before" result))
    (should (string-match-p "after" result))))

;;; --- blueprint--ai-clamp ---

(ert-deftest blueprint-test-ai/clamp-short-text ()
  "Text shorter than the limit is returned unchanged."
  (let ((blueprint-ai-max-context 100)
        (text "Short text."))
    (should (string= text (blueprint--ai-clamp text)))))

(ert-deftest blueprint-test-ai/clamp-exact-limit ()
  "Text exactly at the limit is returned unchanged."
  (let* ((blueprint-ai-max-context 10)
         (text (make-string 10 ?a)))
    (should (string= text (blueprint--ai-clamp text)))))

(ert-deftest blueprint-test-ai/clamp-over-limit ()
  "Text longer than the limit is truncated to exactly the limit."
  (let ((blueprint-ai-max-context 10)
        (text (make-string 20 ?x)))
    (let ((result (blueprint--ai-clamp text)))
      (should (= 10 (length result))))))

(ert-deftest blueprint-test-ai/clamp-empty-string ()
  "Empty string is returned unchanged."
  (let ((blueprint-ai-max-context 100))
    (should (string= "" (blueprint--ai-clamp "")))))

;;; --- blueprint--ai-prepare-context ---

(ert-deftest blueprint-test-ai/prepare-context-sanitizes-and-clamps ()
  "prepare-context both sanitizes and clamps the text."
  (let ((blueprint-ai-max-context 30)
        (text "Contact admin@test.com for very long detailed information about the system."))
    (let ((result (blueprint--ai-prepare-context text)))
      ;; Should be clamped
      (should (<= (length result) 30))
      ;; Should be sanitized (if email falls within the 30-char window)
      (should-not (string-match-p "@test.com" result)))))

(provide 'blueprint-test-ai)
;;; blueprint-test-ai.el ends here
