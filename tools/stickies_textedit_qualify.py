#!/usr/bin/env python3
"""Inspect genuine macOS TextEdit RTFD fixtures against supported contracts.

This command does not emulate AppKit, render visual screenshots, or certify a
TextEdit UI round trip. It checks actual supplied package bytes without writing
or modifying the source. The final TextEdit open/save comparison is manual.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path
import sys

import stickies_rtfd as rtfd


def inspect_fixture(source: Path) -> dict[str, object]:
    """Return a bounded, stable report from one validated RTFD package."""
    text, formatting, assets = rtfd.inspect_package(source)
    native = rtfd.read_native_note(source, assets)
    if native is None:
        native = rtfd._external_note(source, assets)
    if native is not None:
        text, formatting, _ = native
    styles = sorted({
        line.split(":", 2)[2]
        for line in formatting.splitlines() if line.count(":") == 2
    })
    return {
        "text_sha256": sha256(text.encode("utf-8")).hexdigest(),
        "formatting_sha256": sha256(formatting.encode("utf-8")).hexdigest(),
        "paragraph_styles": [item for item in styles if item.startswith("para-")],
        "list_styles": [item for item in styles if item.startswith("list-")],
        "attachments": sorted(path.name for path in assets),
        "inline_images": text.count("\ufffc"),
        "text": text,
    }


def check_fixture(source: Path, expected: dict[str, object]) -> dict[str, object]:
    """Fail on any explicitly asserted, source-grounded fixture property."""
    report = inspect_fixture(source)
    supported = set(report) | {"required_styles"}
    for name, value in expected.items():
        if name not in supported:
            raise ValueError("Unsupported fixture expectation: " + name)
        if name == "required_styles":
            if not isinstance(value, list) or any(
                not isinstance(item, str) for item in value
            ):
                raise ValueError("required_styles must be an array of tokens")
            found = report["paragraph_styles"] + report["list_styles"]
            if not all(item in found for item in value):
                raise ValueError("TextEdit document lost required formatting")
        elif report[name] != value:
            raise ValueError("TextEdit fixture mismatch: " + name)
    return report


def main(argv: list[str] | None = None) -> int:
    """Report source-backed structure; optionally compare with expected fields."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Real TextEdit .rtfd directory")
    parser.add_argument(
        "--expected", type=Path, help="Optional expected JSON property file"
    )
    args = parser.parse_args(argv)
    try:
        expected: dict[str, object] = {}
        if args.expected is not None:
            if args.expected.is_symlink() or args.expected.stat().st_size > 128 * 1024:
                raise ValueError("Expected fixture report must be a bounded regular file")
            value = json.loads(args.expected.read_text(encoding="utf-8"))
            if not isinstance(value, dict):
                raise ValueError("Expected fixture report must be a JSON object")
            expected = value
        report = check_fixture(args.source, expected)
        print(json.dumps(report, sort_keys=True, ensure_ascii=True))
    except (OSError, ValueError, rtfd.RtfdError,
            rtfd.RtfImportError, rtfd.RtfExportError) as error:
        print("TextEdit fixture qualification failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
