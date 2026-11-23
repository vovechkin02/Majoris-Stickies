#!/usr/bin/env python3
"""Import a bounded, text-only RTF subset into Majoris Stickies formatting.

No RTF objects, hyperlinks, field instructions, external resources, attachments,
macros, or embedded data are evaluated. Unsupported metadata destinations are
skipped; the original file is never modified. Imported body text is not a
lossless representation of RTF documents with unsupported constructs.
"""

from __future__ import annotations

import argparse
import os
import re
import stat
import sys
from pathlib import Path
from urllib.parse import quote

MAX_INPUT_BYTES = 16 * 1024 * 1024
MAX_OUTPUT_BYTES = 2 * 1024 * 1024
MAX_SPANS = 20_000
MAX_DEPTH = 64
MAX_CONTROL_LENGTH = 48
TRANSFER_SEPARATOR = "\x1e"
SKIPPED_DESTINATIONS = frozenset(
    {
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "object",
        "header", "footer", "headerl", "headerr", "footerl", "footerr",
        "generator", "listtable", "listoverridetable", "revtbl", "xmlnstbl",
        "datastore", "themedata", "colorschememapping", "fldinst",
    }
)
STYLE_GROUPS = {
    "bold": {"bold"},
    "italic": {"italic"},
    "underline": {"underline"},
    "strikethrough": {"strikethrough"},
    "family": {"font-sans", "font-serif", "font-monospace"},
    "alignment": {"align-left", "align-center", "align-right"},
    "color": {"text-red", "text-blue", "text-green"},
    "size": {f"size-{point}" for point in (10, 12, 14, 16, 18, 20, 24)},
}


MAX_TABLE_BYTES = 64 * 1024
MAX_TABLE_ENTRIES = 256
KNOWN_COLORS = {
    "text-red": (180, 35, 24),
    "text-blue": (21, 94, 239),
    "text-green": (6, 118, 71),
}


def _rtf_table(source: str, name: str) -> str:
    """Locate one bounded group, respecting escaped literal braces."""
    marker = "{" + "\\" + name
    start = source.find(marker)
    if start < 0 and name in ("listtable", "listoverridetable"):
        start = source.find("{" + "\\*\\" + name)
    if start < 0:
        return ""
    depth = 0
    index = start
    while index < len(source) and index - start <= MAX_TABLE_BYTES:
        char = source[index]
        if char == "\\" and index + 1 < len(source) and source[index + 1] in "{}\\":
            index += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
        index += 1
    raise RtfImportError(f"Malformed or oversized {name} RTF table")


def _parse_font_table(source: str) -> dict[int, str]:
    """Map declared RTF font IDs to supported families, not fixed indices."""
    table = _rtf_table(source, "fonttbl")
    result: dict[int, str] = {}
    if not table:
        return result
    entries = re.findall(r"\{\\f(\d+)([^{}]{0,512});\}", table)
    if len(entries) > MAX_TABLE_ENTRIES:
        raise RtfImportError("RTF font table has too many entries")
    for raw_index, definition in entries:
        index = int(raw_index)
        if index > 65535:
            continue
        # Preserve declared font families rather than collapsing every family
        # to serif/sans/monospace. Keep the historical token for the three
        # standard export fonts so older imports stay byte-for-byte stable.
        clean_name = re.sub(r"\\[a-zA-Z]+-?\d* ?", "", definition).strip()
        lower_name = clean_name.lower()
        if lower_name in {"arial", "helvetica"}:
            result[index] = "font-sans"
        elif lower_name in {"times new roman", "times"}:
            result[index] = "font-serif"
        elif lower_name in {"courier new", "courier"}:
            result[index] = "font-monospace"
        elif (clean_name and len(clean_name.encode("utf-8")) <= 96 and
              all(ord(character) >= 32 and ord(character) != 127 and
                  character not in ":\\" for character in clean_name)):
            result[index] = "face_" + quote(clean_name, safe="")
        elif "\\fmodern" in definition:
            result[index] = "font-monospace"
        elif "\\froman" in definition:
            result[index] = "font-serif"
        elif "\\fswiss" in definition:
            result[index] = "font-sans"
    return result


def _groups_by_control(table: str, control: str) -> list[str]:
    """Extract bounded brace groups for exact control words, never evaluate them."""
    groups: list[str] = []
    marker = "{" + "\\" + control
    for candidate in re.finditer(re.escape(marker) + r"(?=[\\ {])", table):
        index = candidate.start()
        depth = 0
        while index < len(table):
            char = table[index]
            if char == "\\" and index + 1 < len(table) and table[index + 1] in "{}\\":
                index += 2
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    groups.append(table[candidate.start():index + 1])
                    break
            index += 1
        if len(groups) > MAX_TABLE_ENTRIES:
            raise RtfImportError("RTF list metadata has too many entries")
    return groups


def _parse_list_kinds(source: str) -> dict[int, dict[int, str]]:
    """Resolve common RTF list overrides and six bounded level-number formats.

    It recognizes only declarative `listid`, `ls`, and `levelnfc` metadata. Any
    complex bullet glyph, field, executable object, or stylesheet is ignored.
    """
    definitions: dict[int, dict[int, str]] = {}
    table = _rtf_table(source, "listtable")
    for group in _groups_by_control(table, "list"):
        list_id = re.search(r"\\listid([0-9]{1,6})(?![0-9])", group)
        if list_id is None:
            continue
        levels: dict[int, str] = {}
        for index, level in enumerate(_groups_by_control(group, "listlevel")[:6]):
            numbering = re.search(r"\\levelnfc([0-9]{1,3})(?![0-9])", level)
            if numbering is None:
                continue
            value = int(numbering.group(1))
            if value in (23, 255):
                levels[index] = "list-bullet"
            elif 0 <= value <= 5:
                levels[index] = "list-numbered"
        definitions[int(list_id.group(1))] = levels
    overrides = _rtf_table(source, "listoverridetable")
    result: dict[int, dict[int, str]] = {}
    for group in _groups_by_control(overrides, "listoverride"):
        identifier = re.search(r"\\listid([0-9]{1,6})(?![0-9])", group)
        selector = re.search(r"\\ls([0-9]{1,6})(?![0-9])", group)
        if identifier is not None and selector is not None:
            values = definitions.get(int(identifier.group(1)))
            if values is not None:
                result[int(selector.group(1))] = values
    return result


def _parse_color_table(source: str) -> dict[int, str]:
    """Read actual color entries and map only sufficiently similar colors."""
    table = _rtf_table(source, "colortbl")
    result: dict[int, str] = {}
    if not table:
        return result
    entries = table.split(";", MAX_TABLE_ENTRIES + 1)
    if len(entries) > MAX_TABLE_ENTRIES + 1:
        raise RtfImportError("RTF color table has too many entries")
    for index, entry in enumerate(entries[:-1]):
        channels = {}
        for channel, raw in re.findall(r"\\(red|green|blue)(\d{1,3})(?!\d)", entry):
            channels[channel] = int(raw)
        if len(channels) != 3 or any(value > 255 for value in channels.values()):
            continue
        rgb = (channels["red"], channels["green"], channels["blue"])
        known = next(
            (name for name, known_rgb in KNOWN_COLORS.items() if known_rgb == rgb),
            None,
        )
        legacy_aliases = {
            (255, 0, 0): "text-red", (0, 0, 255): "text-blue",
            (0, 128, 0): "text-green",
        }
        result[index] = (
            known or legacy_aliases.get(rgb) or
            "rgb_" + "".join(f"{value:02x}" for value in rgb)
        )
    return result


class RtfImportError(ValueError):
    """Indicate that an RTF file cannot safely be converted."""


class RtfReader:
    """Parse a finite RTF text stream and produce stable Unicode style spans."""

    def __init__(self) -> None:
        """Allocate bounded per-document parser state."""
        self.chars: list[str] = []
        self.styles: set[str] = set()
        self.starts: dict[str, int] = {}
        self.spans: list[tuple[int, int, str]] = []
        self.stack: list[tuple[set[str], bool, int, bool]] = []
        self.hidden = False
        self.in_list_marker = False
        self.uc = 1
        self.fallback = 0
        self.pending_high: int | None = None
        self.output_bytes = 0
        self.fonts: dict[int, str] = {}
        self.colors: dict[int, str] = {}
        self.legacy_codec = "cp1252"
        self.paragraph_start = 0
        self.paragraph_metrics: dict[str, int] = {}
        self.paragraph_tabs: list[tuple[int, str]] = []
        self.pending_tab_alignment = "L"
        self.paragraph_list_id = 0
        self.paragraph_list_level = 0
        self.list_kinds: dict[int, dict[int, str]] = {}

    def _set_style(self, group: str, style: str | None) -> None:
        """Keep one active style per mutually exclusive formatting group."""
        # Dynamic face/rgb/point tokens belong to the same exclusive groups
        # as the earlier fixed palette and must not accumulate across runs.
        dynamic_prefix = {
            "family": "face_", "color": "rgb_", "size": "point_",
        }.get(group)
        if dynamic_prefix is not None:
            self.styles = {
                item for item in self.styles
                if not item.startswith(dynamic_prefix)
            }
        self.styles.difference_update(STYLE_GROUPS[group])
        if style is not None:
            self.styles.add(style)

    def _record_paragraph(self) -> None:
        """Keep supported paragraph geometry on one current text interval."""
        end = len(self.chars)
        if end <= self.paragraph_start:
            return
        for kind in ("li", "ri", "fi"):
            if kind in self.paragraph_metrics:
                value = self.paragraph_metrics[kind]
                self.spans.append((
                    self.paragraph_start, end, f"para-{kind}_{value}",
                ))
        if self.paragraph_tabs:
            tabs = "_".join(
                f"{position}{alignment}"
                for position, alignment in sorted(self.paragraph_tabs)
            )
            self.spans.append((
                self.paragraph_start, end, "para-tabs_" + tabs,
            ))
        if self.paragraph_list_id > 0:
            level = self.paragraph_list_level
            if 0 <= level <= 5:
                self.spans.append((
                    self.paragraph_start, end, f"list-depth-{level + 1}",
                ))
            prefix = "".join(self.chars[self.paragraph_start:end]).lstrip()
            if prefix.startswith(("• ", "· ")):
                self.spans.append((
                    self.paragraph_start, end, "list-bullet",
                ))
            elif re.match(r"[1-9][0-9]{0,5}\. ", prefix):
                self.spans.append((
                    self.paragraph_start, end, "list-numbered",
                ))
            else:
                # Level metadata is deliberately resolved only from RTF's
                # declared list tables, never an unknown \ls identifier.
                list_kind = self.list_kinds.get(self.paragraph_list_id, {}).get(
                    self.paragraph_list_level
                )
                if list_kind is not None:
                    self.spans.append((
                        self.paragraph_start, end, list_kind,
                    ))
        if len(self.spans) > MAX_SPANS:
            raise RtfImportError("RTF contains too many formatting intervals")

    def _end_paragraph(self) -> None:
        """Commit properties before emitting a portable line separator."""
        self._flush_high()
        self._record_paragraph()
        self._emit("\n")
        self.paragraph_start = len(self.chars)

    def _append(self, char: str) -> None:
        """Emit one visible code point and record transitions at its offset."""
        if char == TRANSFER_SEPARATOR or char == "\x00":
            raise RtfImportError("RTF contains an unsupported control character")
        new_bytes = len(char.encode("utf-8"))
        if self.output_bytes + new_bytes > MAX_OUTPUT_BYTES:
            raise RtfImportError("RTF text exceeds 2 MiB")
        offset = len(self.chars)
        for style in self.starts.keys() - self.styles:
            self.spans.append((self.starts.pop(style), offset, style))
        for style in self.styles - self.starts.keys():
            self.starts[style] = offset
        if len(self.spans) > MAX_SPANS:
            raise RtfImportError("RTF contains too many formatting intervals")
        self.chars.append(char)
        self.output_bytes += new_bytes

    def _flush_high(self) -> None:
        """Replace an unpaired UTF-16 high surrogate with U+FFFD."""
        if self.pending_high is not None:
            self.pending_high = None
            self._append("\ufffd")

    def _emit(self, char: str) -> None:
        """Apply RTF Unicode fallback handling to ordinary visible text."""
        if self.hidden:
            return
        if self.fallback:
            self.fallback -= 1
            return
        self._flush_high()
        # Apple TextEdit and Word commonly use a listtext/pntext group with
        # a middle-dot marker and a tab. Convert that to portable list-marker
        # text without evaluating the RTF list table or creating a second
        # persistent document model.
        if self.in_list_marker and char in ("·", "●", "◦"):
            char = "•"
        if self.in_list_marker and char == "	":
            char = " "
        self._append(char)

    def _emit_unicode(self, signed_unit: int) -> None:
        """Decode signed UTF-16 RTF units, including surrogate pairs."""
        if self.hidden:
            return
        code = signed_unit & 0xFFFF
        if 0xDC00 <= code <= 0xDFFF and self.pending_high is not None:
            codepoint = 0x10000 + ((self.pending_high - 0xD800) << 10) + code - 0xDC00
            self.pending_high = None
            self._append(chr(codepoint))
        else:
            self._flush_high()
            if 0xD800 <= code <= 0xDBFF:
                self.pending_high = code
            elif 0xDC00 <= code <= 0xDFFF:
                self._append("\ufffd")
            else:
                self._append(chr(code))
        self.fallback = self.uc

    def _control(self, word: str, value: int | None) -> None:
        """Interpret only bounded, non-executable text-formatting controls."""
        if word == "bin":
            raise RtfImportError("Binary RTF objects are not supported")
        if word in SKIPPED_DESTINATIONS:
            self.hidden = True
        if self.hidden:
            return
        if word in ("par", "line"):
            self._end_paragraph()
        elif word == "pard":
            self.paragraph_metrics.clear()
            self.paragraph_tabs.clear()
            self.pending_tab_alignment = "L"
            self.paragraph_list_id = 0
            self.paragraph_list_level = 0
            self._set_style("alignment", None)
        elif word in ("li", "ri", "fi") and value is not None:
            if (not -7200 <= value <= 7200 or
                    (word != "fi" and value < 0)):
                raise RtfImportError("Unsupported paragraph indentation")
            self.paragraph_metrics[word] = value
        elif word in ("tql", "tqc", "tqr", "tqdec"):
            self.pending_tab_alignment = {
                "tql": "L", "tqc": "C", "tqr": "R", "tqdec": "D",
            }[word]
        elif word == "tx" and value is not None:
            if (value <= 0 or value > 7200 or len(self.paragraph_tabs) >= 12 or
                    any(position == value for position, _ in self.paragraph_tabs)):
                raise RtfImportError("Unsupported RTF tab stops")
            self.paragraph_tabs.append((value, self.pending_tab_alignment))
            self.pending_tab_alignment = "L"
        elif word == "ls" and value is not None:
            if value > 0 and value < 65536:
                self.paragraph_list_id = value
        elif word == "ilvl" and value is not None:
            if 0 <= value <= 5:
                self.paragraph_list_level = value
        elif word == "tab":
            self._emit("\t")
        elif word == "u" and value is not None:
            self._emit_unicode(value)
        elif word == "uc" and value is not None:
            self.uc = max(0, min(value, 4))
        elif word == "mac":
            self.legacy_codec = "mac_roman"
        elif word == "ansi":
            self.legacy_codec = "cp1252"
        elif word == "ansicpg" and value is not None:
            if value == 65001:
                self.legacy_codec = "utf-8"
            elif value == 10000:
                self.legacy_codec = "mac_roman"
            elif value == 1252:
                self.legacy_codec = "cp1252"
        elif word in ("b", "i", "ul", "strike"):
            group, style = {
                "b": ("bold", "bold"), "i": ("italic", "italic"),
                "ul": ("underline", "underline"),
                "strike": ("strikethrough", "strikethrough"),
            }[word]
            self._set_style(group, style if value != 0 else None)
        elif word in ("ulnone", "ul0"):
            self._set_style("underline", None)
        elif word == "f" and value is not None:
            self._set_style("family", self.fonts.get(value))
        elif word == "fs" and value is not None:
            if value % 2 == 0 and 16 <= value <= 144:
                points = value // 2
                selected = (f"size-{points}" if f"size-{points}" in
                            STYLE_GROUPS["size"] else f"point_{points}")
                self._set_style("size", selected)
            else:
                self._set_style("size", None)
        elif word == "cf" and value is not None:
            self._set_style("color", self.colors.get(value))
        elif word in ("ql", "qc", "qr", "qj"):
            self._set_style("alignment", {
                "ql": "align-left", "qc": "align-center", "qr": "align-right",
            }.get(word))
        elif word == "plain":
            self.styles.clear()

    def parse(self, data: bytes) -> tuple[str, str]:
        """Convert an RTF document to plain text and app-owned style intervals."""
        if len(data) > MAX_INPUT_BYTES or not data.lstrip().startswith(b"{\\rtf1"):
            raise RtfImportError("Expected an RTF 1 document of at most 16 MiB")
        if b"\x00" in data:
            raise RtfImportError("RTF contains NUL bytes")
        source = data.decode("latin-1")
        self.fonts = _parse_font_table(source)
        self.colors = _parse_color_table(source)
        self.list_kinds = _parse_list_kinds(source)
        index = 0
        optional_destination = False
        while index < len(source):
            char = source[index]
            if not self.stack and char not in "{\r\n \t":
                raise RtfImportError("RTF contains data outside the root group")
            if char == "{":
                if len(self.stack) >= MAX_DEPTH:
                    raise RtfImportError("RTF group depth exceeds 64")
                self.stack.append((
                    set(self.styles), self.hidden, self.uc, self.in_list_marker
                ))
                if (source[index + 1:].startswith("\\listtext") or
                        source[index + 1:].startswith("\\pntext")):
                    self.in_list_marker = True
                optional_destination = False
                index += 1
            elif char == "}":
                if not self.stack:
                    raise RtfImportError("RTF contains an unmatched group terminator")
                self._flush_high()
                (
                    self.styles, self.hidden, self.uc, self.in_list_marker
                ) = self.stack.pop()
                optional_destination = False
                index += 1
            elif char == "\\":
                index += 1
                if index >= len(source):
                    raise RtfImportError("RTF ends with an incomplete escape")
                symbol = source[index]
                if symbol in "{}\\":
                    self._emit(symbol)
                    index += 1
                elif symbol == "'":
                    # A single Unicode character can occupy multiple adjacent
                    # RTF byte escapes when ansicpg65001 is selected.
                    octets = bytearray()
                    while True:
                        if index + 2 >= len(source):
                            raise RtfImportError("RTF hex escape is incomplete")
                        try:
                            octets.append(int(source[index + 1:index + 3], 16))
                        except ValueError as error:
                            raise RtfImportError("RTF hex escape is invalid") from error
                        index += 3
                        if source[index:index + 2] != "\\'":
                            break
                        index += 1
                    for decoded in octets.decode(self.legacy_codec, errors="replace"):
                        self._emit(decoded)
                elif symbol == "*":
                    optional_destination = True
                    index += 1
                elif symbol in "~-_":
                    self._emit({"~": "\u00a0", "-": "\u00ad", "_": "\u2011"}[symbol])
                    index += 1
                elif symbol.isalpha() and symbol.isascii():
                    start = index
                    while (
                        index < len(source)
                        and source[index].isascii()
                        and source[index].isalpha()
                    ):
                        index += 1
                        if index - start > MAX_CONTROL_LENGTH:
                            raise RtfImportError("RTF control word is too long")
                    word = source[start:index]
                    sign = 1
                    if index < len(source) and source[index] == "-":
                        sign = -1
                        index += 1
                    number_start = index
                    while (
                        index < len(source)
                        and source[index].isascii()
                        and source[index].isdigit()
                    ):
                        index += 1
                        if index - number_start > 10:
                            raise RtfImportError("RTF control number is too large")
                    value = (
                        int(source[number_start:index]) * sign
                        if index > number_start else None
                    )
                    if index < len(source) and source[index] == " ":
                        index += 1
                    if optional_destination:
                        self.hidden = True
                        optional_destination = False
                    self._control(word, value)
                else:
                    index += 1
            elif char in "\r\n":
                index += 1
            else:
                displayed = (
                    char if ord(char) < 128
                    else bytes([ord(char)]).decode(
                        self.legacy_codec, errors="replace"
                    )
                )
                self._emit(displayed)
                index += 1
        if self.stack:
            raise RtfImportError("RTF document has unmatched groups")
        self._flush_high()
        self._record_paragraph()
        for style, start in self.starts.items():
            self.spans.append((start, len(self.chars), style))
        if len(self.spans) > MAX_SPANS:
            raise RtfImportError("RTF contains too many formatting intervals")
        text = "".join(self.chars)
        formatting = "".join(
            f"{start}:{end}:{style}\n" for start, end, style in sorted(self.spans)
            if start < end
        )
        if len(formatting.encode("utf-8")) > 1024 * 1024:
            raise RtfImportError("RTF formatting exceeds 1 MiB")
        return text, formatting


def import_rtf(path: Path) -> tuple[str, str]:
    """Read only local regular files within the configured size limit."""
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise RtfImportError("Cannot open local RTF input") from error
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_INPUT_BYTES:
            raise RtfImportError("Only regular RTF files up to 16 MiB are supported")
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            data = source.read(MAX_INPUT_BYTES + 1)
    finally:
        os.close(descriptor)
    return RtfReader().parse(data)


def main(argv: list[str] | None = None) -> int:
    """Return text and formatting through a private subprocess-only separator."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Local RTF document")
    args = parser.parse_args(argv)
    try:
        text, formatting = import_rtf(args.source)
        payload = (text + TRANSFER_SEPARATOR + formatting).encode("utf-8")
        sys.stdout.buffer.write(payload)
    except (OSError, RtfImportError, UnicodeError) as error:
        print(f"RTF import failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
