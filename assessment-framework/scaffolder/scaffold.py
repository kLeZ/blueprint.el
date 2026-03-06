#!/usr/bin/env python3
"""
scaffold.py -- Assessment project scaffolder.

Daily-use tool for managing the org-mode document structure of an
architectural assessment project.

Usage:
  scaffold.py init <project-dir> [--client <name>] [--author <name>]
  scaffold.py add-component <component-id> <component-name> [--project <dir>]
  scaffold.py remove-component <component-id> [--project <dir>]
  scaffold.py list [--project <dir>]
  scaffold.py status [--project <dir>]
  scaffold.py add-term <term> <definition> [--project <dir>] [--source <source>]
  scaffold.py add-reference <type> [--project <dir>]
  scaffold.py add-question <component-id> <question> [--project <dir>]
  scaffold.py sync-master [--project <dir>]
  scaffold.py export [--project <dir>] [--format <docx|pdf>]
  scaffold.py --help

Commands:
  init              Initialize a new project directory with full structure.
  add-component     Add a new component (creates arc42, functional, infra files).
  remove-component  Remove a component (moves to _archive, does not delete).
  list              List all components in the project.
  status            Show completion status per component and section.
  add-term          Add a term to the glossary.
  add-reference     Interactively add a reference (document, interview, system).
  add-question      Append an open question to a component's files.
  sync-master       Regenerate #+INCLUDE directives in master.org.
  export            Export master.org to docx or pdf via pandoc.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent.resolve()
TEMPLATES_DIR = SCRIPT_DIR / "templates"
CONFIG_FILE_NAME = ".scaffold.json"
DATE_TODAY = datetime.date.today().isoformat()


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def find_project_root(start: Path) -> Optional[Path]:
    """Walk up from start looking for .scaffold.json."""
    current = start.resolve()
    for parent in [current] + list(current.parents):
        if (parent / CONFIG_FILE_NAME).exists():
            return parent
    return None


def load_config(project_dir: Path) -> dict:
    config_path = project_dir / CONFIG_FILE_NAME
    if not config_path.exists():
        die(f"No project config found at {config_path}. Run 'init' first.")
    with open(config_path) as f:
        return json.load(f)


def save_config(project_dir: Path, config: dict):
    config_path = project_dir / CONFIG_FILE_NAME
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def die(msg: str):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg: str):
    print(f"  {msg}")


# ---------------------------------------------------------------------------
# Template rendering
# ---------------------------------------------------------------------------

def render_template(template_name: str, replacements: dict) -> str:
    template_path = TEMPLATES_DIR / template_name
    if not template_path.exists():
        die(f"Template not found: {template_path}")
    content = template_path.read_text(encoding="utf-8")
    for key, value in replacements.items():
        content = content.replace(f"[{key}]", value)
    return content


def write_file(path: Path, content: str, overwrite: bool = False):
    if path.exists() and not overwrite:
        info(f"SKIP (exists): {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    info(f"WRITE: {path}")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_init(args):
    project_dir = Path(args.project_dir).resolve()

    if project_dir.exists() and any(project_dir.iterdir()):
        print(f"WARNING: Directory {project_dir} is not empty.")
        answer = input("Continue? [y/N] ").strip().lower()
        if answer != "y":
            sys.exit(0)

    client_name = args.client or "CLIENT"
    author = args.author or "AUTHOR"

    replacements = {
        "CLIENT_NAME": client_name,
        "AUTHOR": author,
        "DATE": DATE_TODAY,
    }

    print(f"\nInitializing project in: {project_dir}")

    # Directory structure
    dirs = [
        project_dir / "enterprise",
        project_dir / "components",
        project_dir / "nfr",
        project_dir / "methodology",
        project_dir / "_archive",
    ]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)
        info(f"DIR: {d}")

    # Root files
    write_file(
        project_dir / "master.org",
        render_template("master.org", replacements)
    )
    write_file(
        project_dir / "glossary.org",
        render_template("glossary.org", {"DATE": DATE_TODAY})
    )
    write_file(
        project_dir / "references.org",
        render_template("references.org", {"DATE": DATE_TODAY})
    )

    # Enterprise files
    write_file(
        project_dir / "enterprise" / "context.org",
        render_template("enterprise-context.org", {"DATE": DATE_TODAY})
    )
    write_file(
        project_dir / "enterprise" / "dependencies.org",
        render_template("enterprise-dependencies.org", {"DATE": DATE_TODAY})
    )

    # NFR files
    write_file(
        project_dir / "nfr" / "quality-scenarios.org",
        render_template("nfr-quality.org", {"DATE": DATE_TODAY})
    )
    write_file(
        project_dir / "nfr" / "constraints.org",
        render_template("nfr-constraints.org", {"DATE": DATE_TODAY})
    )
    write_file(
        project_dir / "nfr" / "risks.org",
        render_template("nfr-risks.org", {"DATE": DATE_TODAY})
    )

    # Copy methodology
    method_src = SCRIPT_DIR.parent / "methodology" / "METHOD.org"
    if method_src.exists():
        shutil.copy(method_src, project_dir / "methodology" / "METHOD.org")
        info(f"COPY: methodology/METHOD.org")

    # Write CONTEXT.org
    context_src = SCRIPT_DIR.parent / "CONTEXT.org"
    if context_src.exists():
        shutil.copy(context_src, project_dir / "CONTEXT.org")
        info(f"COPY: CONTEXT.org")

    # Save config
    config = {
        "client": client_name,
        "author": author,
        "created": DATE_TODAY,
        "updated": DATE_TODAY,
        "components": {}
    }
    save_config(project_dir, config)
    info(f"CONFIG: {project_dir / CONFIG_FILE_NAME}")

    print(f"\nProject initialized. Next steps:")
    print(f"  cd {project_dir}")
    print(f"  ./scaffold.py add-component <id> <name>")
    print(f"  # Edit master.org to add client name and details")


def cmd_add_component(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)

    comp_id = args.component_id.lower().replace(" ", "-")
    comp_name = args.component_name
    comp_dir = project_dir / "components" / comp_id

    if comp_id in config["components"]:
        die(f"Component '{comp_id}' already exists.")

    replacements = {
        "COMPONENT_NAME": comp_name,
        "COMPONENT_ID": comp_id,
        "DATE": DATE_TODAY,
    }

    print(f"\nAdding component: {comp_id} ({comp_name})")

    write_file(comp_dir / "arc42.org", render_template("arc42.org", replacements))
    write_file(comp_dir / "functional.org", render_template("functional.org", replacements))
    write_file(comp_dir / "infrastructure.org", render_template("infrastructure.org", replacements))

    config["components"][comp_id] = {
        "name": comp_name,
        "added": DATE_TODAY,
        "status": "empty"
    }
    config["updated"] = DATE_TODAY
    save_config(project_dir, config)

    # Update master.org includes
    _sync_master_includes(project_dir, config)

    print(f"\nDone. Files created in: {comp_dir}")


def cmd_remove_component(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)

    comp_id = args.component_id.lower()
    if comp_id not in config["components"]:
        die(f"Component '{comp_id}' not found.")

    comp_dir = project_dir / "components" / comp_id
    archive_dir = project_dir / "_archive" / comp_id

    print(f"Archiving component: {comp_id}")
    if comp_dir.exists():
        shutil.move(str(comp_dir), str(archive_dir))
        info(f"MOVED: {comp_dir} -> {archive_dir}")

    del config["components"][comp_id]
    config["updated"] = DATE_TODAY
    save_config(project_dir, config)

    _sync_master_includes(project_dir, config)
    print("Done. Component archived (not deleted). Edit master.org if needed.")


def cmd_list(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)

    components = config.get("components", {})
    if not components:
        print("No components registered. Use 'add-component' to add one.")
        return

    print(f"\nProject: {config.get('client', '?')} (created: {config.get('created', '?')})")
    print(f"{'ID':<25} {'Name':<35} {'Added':<12} {'Status'}")
    print("-" * 85)
    for comp_id, comp in components.items():
        print(f"{comp_id:<25} {comp['name']:<35} {comp['added']:<12} {comp.get('status','?')}")


def cmd_status(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)

    components = config.get("components", {})
    if not components:
        print("No components registered.")
        return

    print(f"\nStatus report -- {DATE_TODAY}")
    print(f"Project: {config.get('client', '?')}")
    print()

    tag_patterns = {
        "[DA VALIDARE]": "unvalidated",
        "[DA REVISIONARE]": "needs review",
        "[FINDING]": "finding",
        "[APPROVATO": "approved",
    }

    for comp_id, comp in components.items():
        comp_dir = project_dir / "components" / comp_id
        print(f"Component: {comp['name']} ({comp_id})")

        for fname in ["arc42.org", "functional.org", "infrastructure.org"]:
            fpath = comp_dir / fname
            if not fpath.exists():
                print(f"  {fname:<25} MISSING")
                continue

            content = fpath.read_text(encoding="utf-8")
            counts = {label: content.count(tag) for tag, label in tag_patterns.items()}

            flags = []
            for label, count in counts.items():
                if count > 0:
                    flags.append(f"{label}: {count}")

            status_str = ", ".join(flags) if flags else "clean"
            print(f"  {fname:<25} {status_str}")

        # Count open questions
        open_q = 0
        for fname in ["arc42.org", "functional.org", "infrastructure.org"]:
            fpath = comp_dir / fname
            if fpath.exists():
                content = fpath.read_text(encoding="utf-8")
                # Count non-empty lines after "* Open questions"
                in_section = False
                for line in content.splitlines():
                    if "* Open questions" in line:
                        in_section = True
                        continue
                    if in_section and line.startswith("* "):
                        break
                    if in_section and line.strip().startswith("-") and len(line.strip()) > 2:
                        open_q += 1

        if open_q > 0:
            print(f"  {'open questions':<25} {open_q}")
        print()


def cmd_add_term(args):
    project_dir = _resolve_project(args)
    glossary_path = project_dir / "glossary.org"

    if not glossary_path.exists():
        die("glossary.org not found. Run 'init' first.")

    term = args.term
    definition = args.definition
    source = args.source or "non specificata"
    slug = re.sub(r"[^a-z0-9]", "-", term.lower())

    entry = f"""
** {term}
<<glossary-{slug}>>
{definition}
/Fonte: {source}/
"""

    content = glossary_path.read_text(encoding="utf-8")

    # Insert under "* Termini di dominio"
    insert_after = "<<glossary-domain>>"
    if insert_after in content:
        content = content.replace(insert_after, insert_after + "\n" + entry, 1)
    else:
        content += "\n" + entry

    glossary_path.write_text(content, encoding="utf-8")
    print(f"Term '{term}' added to glossary.")


def cmd_add_reference(args):
    project_dir = _resolve_project(args)
    references_path = project_dir / "references.org"

    if not references_path.exists():
        die("references.org not found. Run 'init' first.")

    ref_type = args.ref_type.lower()
    content = references_path.read_text(encoding="utf-8")

    if ref_type == "document":
        print("Adding document reference.")
        title = input("  Title: ").strip()
        owner = input("  Author/Owner: ").strip()
        date = input(f"  Date [{DATE_TODAY}]: ").strip() or DATE_TODAY
        notes = input("  Notes (optional): ").strip()
        ref_id = _next_ref_id(content, "D")
        row = f"| {ref_id} | {title} | {owner} | {date} | Documento | {notes} |"
        content = _insert_table_row(content, "<<references-documents>>", row)

    elif ref_type == "interview":
        print("Adding interview reference.")
        person = input("  Interviewee name: ").strip()
        role = input("  Role: ").strip()
        date = input(f"  Date [{DATE_TODAY}]: ").strip() or DATE_TODAY
        topics = input("  Topics: ").strip()
        ref_id = _next_ref_id(content, "I")
        row = f"| {ref_id} | {person} | {role} | {date} | {topics} |  |"
        content = _insert_table_row(content, "<<references-interviews>>", row)

    elif ref_type == "system":
        print("Adding system/tool reference.")
        name = input("  System name: ").strip()
        version = input("  Version: ").strip()
        purpose = input("  Purpose in project: ").strip()
        ref_id = _next_ref_id(content, "S")
        row = f"| {ref_id} | {name} | {version} | {purpose} |"
        content = _insert_table_row(content, "<<references-systems>>", row)

    else:
        die(f"Unknown reference type '{ref_type}'. Use: document, interview, system.")

    references_path.write_text(content, encoding="utf-8")
    print(f"Reference {ref_id} added.")


def cmd_add_question(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)

    comp_id = args.component_id.lower()
    question = args.question

    if comp_id not in config["components"]:
        die(f"Component '{comp_id}' not found.")

    comp_dir = project_dir / "components" / comp_id
    modified = []

    for fname in ["arc42.org", "functional.org", "infrastructure.org"]:
        fpath = comp_dir / fname
        if not fpath.exists():
            continue
        content = fpath.read_text(encoding="utf-8")
        if "* Open questions" in content:
            # Append question to open questions section
            content = re.sub(
                r"(\* Open questions\n)((?:- .*\n?)*)",
                lambda m: m.group(1) + m.group(2) + f"- {question}\n",
                content
            )
            fpath.write_text(content, encoding="utf-8")
            modified.append(fname)
            break  # Only add to first file that has the section

    if modified:
        print(f"Question added to {comp_id}/{modified[0]}")
    else:
        print(f"WARNING: 'Open questions' section not found in {comp_id}. Question not added.")


def cmd_sync_master(args):
    project_dir = _resolve_project(args)
    config = load_config(project_dir)
    _sync_master_includes(project_dir, config)
    print("master.org INCLUDE directives updated.")


def cmd_export(args):
    project_dir = _resolve_project(args)
    fmt = getattr(args, "format", "docx") or "docx"
    master = project_dir / "master.org"

    if not master.exists():
        die("master.org not found.")

    output_name = f"assessment-{DATE_TODAY}.{fmt}"
    output_path = project_dir / output_name

    cmd = ["pandoc", str(master), "-o", str(output_path)]

    if fmt == "docx":
        ref_doc = project_dir / "template.docx"
        if ref_doc.exists():
            cmd += ["--reference-doc", str(ref_doc)]
        else:
            print("NOTE: No template.docx found. Using pandoc default Word styles.")
            print("      To use client styles: place template.docx in project root.")
    elif fmt == "pdf":
        cmd += ["--pdf-engine=pdflatex"]

    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"ERROR: pandoc failed.\n{result.stderr}")
        sys.exit(1)

    print(f"Output: {output_path}")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _resolve_project(args) -> Path:
    if hasattr(args, "project") and args.project:
        return Path(args.project).resolve()
    # Auto-detect from cwd
    found = find_project_root(Path.cwd())
    if found:
        return found
    die("No project found. Run from inside a project directory or use --project.")


def _sync_master_includes(project_dir: Path, config: dict):
    master_path = project_dir / "master.org"
    if not master_path.exists():
        return

    content = master_path.read_text(encoding="utf-8")

    # Build the include blocks for part II and III and IV
    part2_includes = []
    part3_includes = []
    part4_includes = []

    for comp_id in config.get("components", {}).keys():
        part2_includes.append(f'#+INCLUDE: "components/{comp_id}/arc42.org" :minlevel 2')
        part3_includes.append(f'#+INCLUDE: "components/{comp_id}/functional.org" :minlevel 2')
        part4_includes.append(f'#+INCLUDE: "components/{comp_id}/infrastructure.org" :minlevel 2')

    def replace_section_includes(text: str, part_anchor: str, new_includes: list) -> str:
        """
        Replace the content between a comment block and the next ----- separator
        with the new includes, preserving the comment block.
        """
        pattern = re.compile(
            r"(#\+begin_comment\nAggiungere un #\+INCLUDE per ogni componente nel perimetro\.[^#]+#\+end_comment\n)"
            r"((?:#\+INCLUDE:.*\n)*)",
            re.MULTILINE
        )
        replacement_includes = "\n".join(new_includes) + "\n" if new_includes else ""
        new_text, count = pattern.subn(r"\g<1>" + replacement_includes, text)
        return new_text

    # We do a simpler replacement: find comment blocks and replace following INCLUDE lines
    for part_includes in [(part2_includes, "Parte II"), (part3_includes, "Parte III"), (part4_includes, "Parte IV")]:
        includes_list, _ = part_includes
        # Find the comment block specific to each part and rebuild includes after it
        pass

    # Simpler approach: rebuild the three include blocks directly
    # For each part, find the comment block end and replace what follows until next -----
    def replace_includes_after_comment(text, comment_keyword, new_includes):
        lines = text.split("\n")
        result = []
        in_comment = False
        comment_ended = False
        includes_replaced = False

        i = 0
        while i < len(lines):
            line = lines[i]

            if "#+begin_comment" in line and not includes_replaced:
                # Check if next lines contain our keyword
                block_lines = []
                j = i
                while j < len(lines) and "#+end_comment" not in lines[j]:
                    block_lines.append(lines[j])
                    j += 1
                block_text = "\n".join(block_lines)
                if comment_keyword in block_text:
                    # Copy comment block
                    while i <= j:
                        result.append(lines[i])
                        i += 1
                    # Skip existing INCLUDE lines
                    while i < len(lines) and lines[i].startswith("#+INCLUDE:"):
                        i += 1
                    # Insert new includes
                    for inc in new_includes:
                        result.append(inc)
                    includes_replaced = True
                    continue
            result.append(line)
            i += 1
        return "\n".join(result)

    content = replace_includes_after_comment(content, "Parte II", part2_includes)
    content = replace_includes_after_comment(content, "Parte III", part3_includes)
    content = replace_includes_after_comment(content, "Parte IV", part4_includes)

    master_path.write_text(content, encoding="utf-8")
    info(f"SYNC: master.org updated with {len(config.get('components', {}))} component(s)")


def _next_ref_id(content: str, prefix: str) -> str:
    """Generate next reference ID like D-001, I-003, etc."""
    pattern = re.compile(rf"\| {prefix}-(\d+) \|")
    existing = [int(m.group(1)) for m in pattern.finditer(content)]
    next_num = max(existing, default=0) + 1
    return f"{prefix}-{next_num:03d}"


def _insert_table_row(content: str, anchor: str, row: str) -> str:
    """Insert a table row after the anchor line, before the closing |----|."""
    if anchor not in content:
        return content + f"\n{row}\n"
    lines = content.split("\n")
    result = []
    anchor_found = False
    for line in lines:
        result.append(line)
        if anchor in line:
            anchor_found = True
        # After anchor, find the separator row and insert before the closing separator
        if anchor_found and re.match(r"^\|[-+|]+\|$", line.strip()):
            # This is a header separator; next non-separator row is data
            # Insert row after this separator
            result.append(row)
            anchor_found = False
    return "\n".join(result)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="scaffold.py -- Assessment project scaffolder",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    subparsers = parser.add_subparsers(dest="command")

    # init
    p_init = subparsers.add_parser("init", help="Initialize a new project")
    p_init.add_argument("project_dir", help="Target directory")
    p_init.add_argument("--client", help="Client name")
    p_init.add_argument("--author", help="Author name")

    # add-component
    p_add = subparsers.add_parser("add-component", help="Add a new component")
    p_add.add_argument("component_id", help="Short identifier (slug, no spaces)")
    p_add.add_argument("component_name", help="Display name")
    p_add.add_argument("--project", help="Project directory (auto-detected if omitted)")

    # remove-component
    p_rm = subparsers.add_parser("remove-component", help="Archive a component")
    p_rm.add_argument("component_id")
    p_rm.add_argument("--project")

    # list
    p_list = subparsers.add_parser("list", help="List components")
    p_list.add_argument("--project")

    # status
    p_status = subparsers.add_parser("status", help="Show completion status")
    p_status.add_argument("--project")

    # add-term
    p_term = subparsers.add_parser("add-term", help="Add glossary term")
    p_term.add_argument("term", help="Term to add")
    p_term.add_argument("definition", help="Definition")
    p_term.add_argument("--project")
    p_term.add_argument("--source", help="Source of the definition")

    # add-reference
    p_ref = subparsers.add_parser("add-reference", help="Add a reference")
    p_ref.add_argument("ref_type", choices=["document", "interview", "system"],
                       help="Type of reference")
    p_ref.add_argument("--project")

    # add-question
    p_q = subparsers.add_parser("add-question", help="Add open question to a component")
    p_q.add_argument("component_id")
    p_q.add_argument("question", help="The open question text")
    p_q.add_argument("--project")

    # sync-master
    p_sync = subparsers.add_parser("sync-master", help="Regenerate master.org INCLUDE directives")
    p_sync.add_argument("--project")

    # export
    p_exp = subparsers.add_parser("export", help="Export to docx or pdf via pandoc")
    p_exp.add_argument("--project")
    p_exp.add_argument("--format", choices=["docx", "pdf"], default="docx")

    args = parser.parse_args()

    dispatch = {
        "init": cmd_init,
        "add-component": cmd_add_component,
        "remove-component": cmd_remove_component,
        "list": cmd_list,
        "status": cmd_status,
        "add-term": cmd_add_term,
        "add-reference": cmd_add_reference,
        "add-question": cmd_add_question,
        "sync-master": cmd_sync_master,
        "export": cmd_export,
    }

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    dispatch[args.command](args)


if __name__ == "__main__":
    main()
