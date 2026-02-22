
# Blueprint (Ultra)

Text-first architectural assessment toolkit for Emacs.

NEW in this build:
- C4 generator with real dependency parsing (# +BLUEPRINT_DEPENDS)
- Health score SVG gauge
- Template diff + migration assistant

Requirements:
- Emacs 29+
- ripgrep (rg)
- graphviz (dot)
- plantuml (optional)
- ollama (optional)

Install:
(add-to-list 'load-path "/path/to/blueprint_ultra")
(require 'blueprint)
C-c b
