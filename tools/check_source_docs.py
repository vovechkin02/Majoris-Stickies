#!/usr/bin/env python3
"""Check Majoris source documentation coverage for Python and Vala declarations.

Vala analysis is deliberately conservative: it scans named types and
method declarations, not generated code or complex macro-like constructs.
Native Valadoc qualification remains required before release.
"""

from __future__ import annotations

import argparse
import ast
import re
from pathlib import Path

VALA_TYPE = re.compile(r"^\s*(?:public|private|internal|protected)?\s*"
                       r"(?:abstract\s+)?(?:class|interface|struct|enum)\s+\w+")
VALA_METHOD = re.compile(r"^\s*(?:public|private|internal|protected)\s+"
                         r"(?:(?:static|override|virtual|async|abstract)\s+)*"
                         r"(?:[A-Za-z_][\w<>?]*\s+)?([A-Za-z_]\w*)\s*\(")
VALA_MAIN = re.compile(r"^int main\s*\(")
VALA_SIGNAL = re.compile(r"^\s*(?:public|private|internal|protected)\s+"
                         r"signal\s+[\w<>?]+\s+\w+\s*\(")
VALA_PROPERTY = re.compile(r"^\s*(?:public|private|internal|protected)\s+"
                           r"[\w<>?]+\s+\w+\s*\{\s*(?:get|set)\s*[;{]")


def check_python(path: Path) -> tuple[int, list[str]]:
    """Inspect module and callable docstrings with Python's actual AST parser."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    nodes = [tree] + [node for node in ast.walk(tree) if isinstance(
        node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
    )]
    missing = [f"{path}:{getattr(node, 'lineno', 1)}: Python docstring missing"
               for node in nodes if not ast.get_docstring(node)]
    return len(nodes), missing


def check_vala(path: Path) -> tuple[int, list[str]]:
    """Require nearby Valadoc comments on handwritten type and method headers."""
    lines = path.read_text(encoding="utf-8").splitlines()
    inspected = 0
    missing = []
    for index, line in enumerate(lines):
        if (VALA_TYPE.match(line) or VALA_METHOD.match(line) or
                VALA_MAIN.match(line) or VALA_SIGNAL.match(line) or
                VALA_PROPERTY.match(line)):
            if "=" in line.split("(")[0]:
                continue
            inspected += 1
            cursor = index - 1
            while cursor >= 0 and lines[cursor].strip() == "":
                cursor -= 1
            # GTK4 templates are legitimate declaration attributes between docs and types.
            if cursor >= 0 and lines[cursor].lstrip().startswith("[GtkTemplate"):
                cursor -= 1
            if cursor < 0 or not lines[cursor].strip().endswith("*/"):
                missing.append(f"{path}:{index + 1}: Valadoc summary missing")
            else:
                prefix = "\n".join(lines[max(0, cursor - 8):cursor + 1])
                if "/**" not in prefix:
                    missing.append(f"{path}:{index + 1}: Valadoc comment missing")
    return inspected, missing


def main() -> int:
    """Report per-language totals and fail when documented declarations are missing."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args()
    root = arguments.root
    reports = []
    for path in sorted((root / "src").rglob("*.vala")):
        reports.append(check_vala(path))
    for directory in ("tools", "tests"):
        for path in sorted((root / directory).rglob("*.py")):
            reports.append(check_python(path))
    count = sum(total for total, _ in reports)
    missing = [message for _, errors in reports for message in errors]
    for message in missing:
        print(message)
    print(f"Source documentation: {count - len(missing)}/{count} declarations documented")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
