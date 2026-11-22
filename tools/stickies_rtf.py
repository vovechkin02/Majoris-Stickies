#!/usr/bin/env python3
"""Export a Stickies note to a bounded, Unicode-safe RTF document.

The exporter never modifies the notes database and refuses to overwrite an
existing destination. RTF is a text interchange format here: managed image
and PDF attachments are deliberately not embedded or exported.
"""

from __future__ import annotations

from contextlib import closing

import argparse
import os
import re
import sqlite3
import sys
from pathlib import Path
from urllib.parse import quote, unquote

MAX_NOTE_BYTES = 2 * 1024 * 1024
MAX_FORMATTING_BYTES = 1024 * 1024
MAX_SPANS = 20_000
MAX_RTF_BYTES = 32 * 1024 * 1024
IDENTIFIER = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
STYLES = {
    "bold": r"\b ",
    "italic": r"\i ",
    "underline": r"\ul ",
    "strikethrough": r"\strike ",
    "monospace": r"\f2 ",
    "font-sans": r"\f0 ",
    "font-serif": r"\f1 ",
    "font-monospace": r"\f2 ",
    "large": r"\fs32 ",
    "small": r"\fs20 ",
    "text-red": r"\cf1 ",
    "text-blue": r"\cf2 ",
    "text-green": r"\cf3 ",
    "align-left": r"\ql ",
    "align-center": r"\qc ",
    "align-right": r"\qr ",
    **{f"size-{size}": rf"\fs{size * 2} " for size in (10, 12, 14, 16, 18, 20, 24)},
}


class RtfExportError(Exception):
    """Explain a rejected note, formatter, or destination."""


def _dynamic_style(style: str) -> bool:
    """Validate bounded rich-text tokens before generating dynamic RTF tables."""
    if style in {"list-bullet", "list-numbered", "list-checklist"}:
        return True
    if re.fullmatch(r"point_([0-9]{1,2})", style):
        value = int(style[6:])
        return 8 <= value <= 72 and style == f"point_{value}"
    if re.fullmatch(r"rgb_[0-9a-f]{6}", style):
        return True
    if re.fullmatch(r"image_[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}_[0-9]{2,4}", style):
        value = int(style.rsplit("_", 1)[1])
        return 96 <= value <= 960 and value % 16 == 0
    if style.startswith("face_") and len(style) <= 240:
        try:
            family = unquote(style[5:], encoding="utf-8", errors="strict")
        except UnicodeError:
            return False
        return (bool(family) and len(family.encode("utf-8")) <= 96 and
                all(ord(char) >= 32 and ord(char) != 127 and char not in ":\\"
                    for char in family) and
                quote(family, safe="") == style[5:])
    return False


def _spans(text: str, formatting: str) -> list[tuple[int, int, str]]:
    """Validate the same half-open Unicode offsets as NoteFormatting."""
    if len(text.encode("utf-8")) > MAX_NOTE_BYTES or len(formatting.encode("utf-8")) > MAX_FORMATTING_BYTES:
        raise RtfExportError("Note text or formatting exceeds the RTF export limit")
    result: list[tuple[int, int, str]] = []
    for line in formatting.splitlines():
        if not line:
            continue
        fields = line.split(":")
        if (len(fields) != 3 or (fields[2] not in STYLES and not _dynamic_style(fields[2])) or
                any(not item.isascii() or not item.isdecimal() for item in fields[:2])):
            raise RtfExportError("Invalid rich-text style interval")
        start, end = int(fields[0]), int(fields[1])
        if not 0 <= start < end <= len(text):
            raise RtfExportError("Formatting position exceeds the note text")
        result.append((start, end, fields[2]))
        if len(result) > MAX_SPANS:
            raise RtfExportError("Too many formatting intervals")
    return result


def _escape_rtf(text: str) -> str:
    """Escape RTF syntax and encode Unicode through signed UTF-16 units."""
    output: list[str] = []
    for char in text:
        if char == "\n":
            output.append("\\par\n")
        elif char == "\t":
            output.append(r"\tab ")
        elif char in "{}\\":
            output.append("\\" + char)
        elif 0x20 <= ord(char) <= 0x7E:
            output.append(char)
        elif ord(char) < 0x20:
            output.append(" ")
        else:
            code_units = char.encode("utf-16-le", errors="surrogatepass")
            for index in range(0, len(code_units), 2):
                unit = code_units[index] | (code_units[index + 1] << 8)
                if unit >= 32768:
                    unit -= 65536
                output.append(rf"\u{unit}?")
    return "".join(output)


def make_rtf(title: str, content: str, formatting: str) -> bytes:
    """Export a portable supported-style subset without an RTF interpreter."""
    if len(title.encode("utf-8")) > 640:
        raise RtfExportError("Note title is too long")
    spans = _spans(content, formatting)
    boundaries: dict[int, list[tuple[str, bool]]] = {}
    for start, end, style in spans:
        boundaries.setdefault(start, []).append((style, True))
        boundaries.setdefault(end, []).append((style, False))
    positions = sorted(set((0, len(content), *boundaries)))
    active: dict[str, int] = {}
    styles = dict(STYLES)
    fonts = [r"{\f0\fswiss Arial;}", r"{\f1\froman Times New Roman;}",
             r"{\f2\fmodern Courier New;}"]
    colors = [(180, 35, 24), (21, 94, 239), (6, 118, 71)]
    for _, _, style in sorted(spans, key=lambda span: span[2]):
        if style in styles:
            continue
        if style.startswith("face_"):
            family = unquote(style[5:], encoding="utf-8", errors="strict")
            index = len(fonts)
            fonts.append(r"{\f" + str(index) + r"\fnil " + _escape_rtf(family) + ";}")
            styles[style] = rf"\f{index} "
        elif style.startswith("rgb_"):
            hex_value = style[4:]
            rgb = tuple(int(hex_value[index:index + 2], 16) for index in (0, 2, 4))
            colors.append(rgb)
            styles[style] = rf"\cf{len(colors)} "
        elif style.startswith("point_"):
            styles[style] = rf"\fs{int(style[6:]) * 2} "
        else:
            # The marker already occurs in ordinary text, and inline media
            # belongs to RTFD attachments rather than an invented RTF object.
            styles[style] = ""
    font_table = r"{\fonttbl" + "".join(fonts) + "}"
    color_table = r"{\colortbl;" + "".join(
        rf"\red{red}\green{green}\blue{blue};"
        for red, green, blue in colors
    ) + "}"
    output = [
        r"{\rtf1\ansi\deff0\uc1", font_table, color_table,
        r"\pard\f0\fs24\b ", _escape_rtf(title), r"\b0\par\par ",
    ]
    for index, position in enumerate(positions[:-1]):
        for style, starting in boundaries.get(position, []):
            if starting:
                active[style] = active.get(style, 0) + 1
            else:
                active[style] = max(0, active.get(style, 0) - 1)
        next_position = positions[index + 1]
        if next_position == position:
            continue
        ordered = sorted(style for style, count in active.items() if count > 0)
        output.extend("{" + styles[style] for style in ordered)
        output.append(_escape_rtf(content[position:next_position]))
        output.extend("}" for _ in ordered)
    output.append("}")
    result = "".join(output).encode("ascii")
    if len(result) > MAX_RTF_BYTES:
        raise RtfExportError("The formatted RTF would exceed 32 MiB")
    return result


def export_note(data_dir: Path, note_id: str, destination: Path) -> None:
    """Read a consistent note snapshot and atomically create the requested RTF."""
    if not IDENTIFIER.fullmatch(note_id):
        raise RtfExportError("Invalid note identifier")
    database = data_dir / "notes.db"
    if not database.is_file() or database.is_symlink():
        raise RtfExportError("No supported notes database was found")
    database_uri = f"file:{quote(str(database.absolute()))}?mode=ro"
    try:
        with closing(sqlite3.connect(database_uri, uri=True, timeout=5)) as connection:
            row = connection.execute(
                "SELECT title, content, formatting FROM notes WHERE id = ? AND status = 0",
                (note_id,),
            ).fetchone()
    except sqlite3.Error as error:
        raise RtfExportError("Cannot read the notes database") from error
    if row is None:
        raise RtfExportError("Note is missing or not active")
    content = make_rtf(*row)
    if not destination.parent.is_dir():
        raise RtfExportError("The destination directory does not exist")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(destination, flags, 0o600)
    except OSError as error:
        raise RtfExportError(f"Cannot create RTF file: {error.strerror}") from error
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
    except OSError:
        destination.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    """Handle a single explicit local export without creating app state."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/majoris/stickies")
    parser.add_argument("note_id", help="UUID of an active note")
    parser.add_argument("destination", type=Path, help="New .rtf file")
    arguments = parser.parse_args(argv)
    try:
        export_note(arguments.data_dir, arguments.note_id, arguments.destination)
    except (RtfExportError, OSError, UnicodeError) as error:
        print(f"RTF export failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
