#!/usr/bin/env bash
# Format the documentation: Markdown with prettier (prose wrapping left
# as it is), Org with scripts/orgfmt.el.  Run from anywhere in the
# repository.
set -e
cd "$(git rev-parse --show-toplevel)"

echo "Formatting markdown"
prettier --write --prose-wrap preserve "**/*.md"

echo "Formatting org"
emacs -Q --batch -l scripts/orgfmt.el

echo "Done"
