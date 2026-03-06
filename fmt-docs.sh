#!/usr/bin/env bash
set -e

echo "Formatting markdown"
prettier --write "**/*.md"

echo "Formatting org"
emacs --batch -l orgfmt.el

echo "Done"
