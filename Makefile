# Development tasks.  Every target runs a clean `emacs -Q --batch`, the
# same way CI does.
#
#   make test                     whole ERT suite
#   make test SELECTOR=health     only the tests whose name matches
#   make compile                  byte-compile, warnings are errors
#   make checkdoc                 docstring conventions on every module
#   make package-lint             package-lint on blueprint.el (needs
#                                 package-lint installed in package.el)
#   make lint                     compile + checkdoc

EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch \
	--eval "(push default-directory load-path)" \
	--eval "(push (expand-file-name \"test\" default-directory) load-path)"

# blueprint-template-history.el is generated; the rest are the modules.
SOURCES  = $(wildcard blueprint*.el)
# The helpers define the macros every suite uses: they load first.
TESTS    = test/blueprint-test-helpers.el \
	$(filter-out test/blueprint-test-helpers.el,$(wildcard test/blueprint-test-*.el))
SELECTOR ?=

.PHONY: test compile checkdoc package-lint lint clean

test:
	$(BATCH) -l blueprint.el $(addprefix -l ,$(TESTS)) \
	  --eval '(ert-run-tests-batch-and-exit "$(SELECTOR)")'

compile:
	$(BATCH) --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(SOURCES); \
	status=$$?; rm -f *.elc; exit $$status

checkdoc:
	@status=0; for f in $(SOURCES); do \
	  $(EMACS) -Q --batch \
	    --eval "(require 'checkdoc)" \
	    --eval "(setq checkdoc-force-docstrings-flag nil)" \
	    --eval "(with-current-buffer (find-file-noselect \"$$f\") \
	              (let ((warnings (checkdoc-file \"$$f\"))) \
	                (when (stringp warnings) \
	                  (message \"%s: %s\" \"$$f\" warnings) \
	                  (kill-emacs 1))))" || status=1; \
	done; exit $$status

package-lint:
	$(EMACS) -Q --batch \
	  --eval "(require 'package)" \
	  --eval "(push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives)" \
	  --eval "(package-initialize)" \
	  --eval "(require 'package-lint)" \
	  --eval "(push default-directory load-path)" \
	  -f package-lint-batch-and-exit blueprint.el

lint: compile checkdoc

clean:
	rm -f *.elc test/*.elc
