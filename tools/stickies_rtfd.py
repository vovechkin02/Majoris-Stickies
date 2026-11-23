#!/usr/bin/env python3
"""Exchange bounded RTFD-style directory packages with local note attachments.

A package contains TXT.rtf and ordinary image/PDF files. Majoris metadata is
optional and does not affect the readable RTF text. This is deliberately a safe,
limited directory interchange format, not full AppKit NSFileWrapper fidelity.
Never follow symlinks, execute RTF objects, or overwrite an existing package.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import re
import shutil
import sqlite3
import stat
import sys
import uuid
from pathlib import Path
from urllib.parse import quote

def _neighbor(name: str, installed_name: str):
    """Load a bundled sibling in a source checkout or Meson installation."""
    folder = Path(__file__).resolve().parent
    candidate = folder / name
    if not candidate.is_file():
        candidate = folder / installed_name
    loader = SourceFileLoader(name, str(candidate))
    spec = importlib.util.spec_from_loader(name, loader)
    if spec is None:
        raise RuntimeError(f"RTFD dependency not installed: {installed_name}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


_rtf_export = _neighbor("stickies_rtf.py", "majoris-stickies-rtf")
_rtf_import = _neighbor("stickies_rtf_import.py", "majoris-stickies-rtf-import")
IDENTIFIER = _rtf_export.IDENTIFIER
RtfExportError = _rtf_export.RtfExportError
make_rtf = _rtf_export.make_rtf
RtfImportError = _rtf_import.RtfImportError
import_rtf = _rtf_import.import_rtf

MAX_ATTACHMENTS = 32
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024
MAX_PACKAGE_BYTES = 128 * 1024 * 1024
MAX_MANIFEST_BYTES = 8 * 1024 * 1024
NEXT_GRAPHIC = re.compile(
    r"\{\{\\NeXTGraphic[ \t]+([^{}\r\n]{1,512})\}[ \t]*(?:¬|\\'ac)?\}",
    flags=re.IGNORECASE,
)
NEXT_GRAPHIC_PROPERTIES = re.compile(r"[ \t]+\\(?:width|height|apple[a-z]+)-?[0-9]*", re.I)
MAX_RTF_GRAPHICS = 32
MIME_SUFFIXES = {
    "image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif",
    "image/tiff": ".tiff", "image/webp": ".webp", "image/bmp": ".bmp",
    "application/pdf": ".pdf", "image/svg+xml": ".svg",
    "image/avif": ".avif", "image/heif": ".heif", "image/heic": ".heic",
}


class RtfdError(ValueError):
    """Report a rejected package or failed local interchange operation."""


def _unique_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    """Reject ambiguous JSON manifests containing duplicate object keys."""
    record: dict[str, object] = {}
    for key, value in pairs:
        if key in record:
            raise RtfdError("Duplicate RTFD metadata field")
        record[key] = value
    return record


def _read_manifest(path: Path) -> dict[str, object]:
    """Load one bounded, non-symlink metadata object with unique fields."""
    _regular_file(path, MAX_MANIFEST_BYTES)
    record = json.loads(
        path.read_text(encoding="utf-8"), object_pairs_hook=_unique_pairs
    )
    if not isinstance(record, dict) or record.get("format") != "majoris-rtfd-1":
        raise RtfdError("Unsupported RTFD metadata format")
    return record


def _regular_file(path: Path, limit: int) -> int:
    """Validate a non-symlink regular file and its finite size."""
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= limit:
        raise RtfdError("Package requires bounded regular files without symlinks")
    return info.st_size


def export_note(data_dir: Path, note_id: str, destination: Path) -> None:
    """Create a new .rtfd directory with RTF and verified managed files."""
    if not IDENTIFIER.fullmatch(note_id):
        raise RtfdError("Invalid note identifier")
    if destination.suffix.lower() != ".rtfd":
        raise RtfdError("The destination must end in .rtfd")
    if not destination.parent.is_dir() or destination.parent.is_symlink():
        raise RtfdError("The destination parent must be a real directory")
    database = data_dir / "notes.db"
    _regular_file(database, 1 << 40)
    uri = f"file:{quote(str(database.absolute()))}?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=5)) as connection:
        connection.execute("BEGIN")
        note = connection.execute(
            "SELECT title,content,formatting FROM notes WHERE id=? AND status=0",
            (note_id,),
        ).fetchone()
        attachments = connection.execute(
            "SELECT id,display_name,mime_type FROM attachments WHERE note_id=? ORDER BY rowid",
            (note_id,),
        ).fetchall()
    if note is None:
        raise RtfdError("The active note was not found")
    if len(attachments) > MAX_ATTACHMENTS:
        raise RtfdError("RTFD package has more than 32 attachments")
    manifest = {
        "format": "majoris-rtfd-1", "attachments": [],
        "native": {"content": note[1], "formatting": note[2]},
    }
    asset_paths: list[tuple[Path, str, int]] = []
    package_bytes = 0
    for index, (identity, display_name, mime) in enumerate(attachments, 1):
        if not IDENTIFIER.fullmatch(identity) or mime not in MIME_SUFFIXES:
            raise RtfdError("Attachment identity or MIME type is not supported")
        source = data_dir / "attachments" / (identity + ".asset")
        length = _regular_file(source, MAX_ATTACHMENT_BYTES)
        package_bytes += length
        if package_bytes > MAX_PACKAGE_BYTES:
            raise RtfdError("RTFD package exceeds 128 MiB")
        name = f"attachment-{index:04d}{MIME_SUFFIXES[mime]}"
        asset_paths.append((source, name, length))
        manifest["attachments"].append(
            {"file": name, "name": display_name[:255], "mime": mime,
             "source_id": identity}
        )
    file_by_identity = {
        record["source_id"]: record["file"]
        for record in manifest["attachments"]
    }
    graphic_positions: dict[int, tuple[str, int]] = {}
    for start, end, style in _rtf_export._spans(note[1], note[2]):
        if not style.startswith("image_"):
            continue
        match = re.fullmatch(
            r"image_([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})_([0-9]{2,4})",
            style,
        )
        if not match or end != start + 1 or note[1][start:end] != "\ufffc":
            raise RtfdError("Invalid inline image location")
        filename = file_by_identity.get(match.group(1))
        if filename is None or not (
            _mime_for_asset(filename) or ""
        ).startswith("image/"):
            raise RtfdError("Inline image not present in the RTFD package")
        graphic_positions[start] = (filename, int(match.group(2)))
    rendered = make_rtf(*note, graphic_positions=graphic_positions)
    package_bytes += len(rendered)
    encoded_manifest = json.dumps(
        manifest, ensure_ascii=True, separators=(",", ":")
    ).encode("utf-8")
    if len(encoded_manifest) > MAX_MANIFEST_BYTES or (package_bytes +
                                                       len(encoded_manifest) > MAX_PACKAGE_BYTES):
        raise RtfdError("RTFD metadata exceeds the safe package size")
    try:
        destination.mkdir(mode=0o700)
    except OSError as error:
        raise RtfdError("Cannot create new RTFD directory") from error
    try:
        (destination / "TXT.rtf").write_bytes(rendered)
        (destination / "majoris.json").write_bytes(encoded_manifest)
        for source, name, expected_length in asset_paths:
            target = destination / name
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            descriptor = os.open(target, flags, 0o600)
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    read_flags = os.O_RDONLY
                    if hasattr(os, "O_NOFOLLOW"):
                        read_flags |= os.O_NOFOLLOW
                    with os.fdopen(os.open(source, read_flags), "rb") as incoming:
                        opened = os.fstat(incoming.fileno())
                        if not stat.S_ISREG(opened.st_mode) or opened.st_size != expected_length:
                            raise RtfdError("Attachment source changed during export")
                        shutil.copyfileobj(incoming, stream, length=256 * 1024)
                    stream.flush()
                    os.fsync(stream.fileno())
                if _regular_file(target, MAX_ATTACHMENT_BYTES) != expected_length:
                    raise RtfdError("An attachment changed during package export")
            except BaseException:
                target.unlink(missing_ok=True)
                raise
    except BaseException:
        shutil.rmtree(destination)
        raise


def _mime_for_asset(name: str) -> str | None:
    """Accept bounded ordinary AppKit filenames without permitting path traversal."""
    if (not name or name in (".", "..") or name.startswith(".") or
            len(name.encode("utf-8")) > 255 or any(
                character in "/\\" or ord(character) < 32 or ord(character) == 127
                for character in name
            )):
        return None
    if name != Path(name).name:
        return None
    suffix = Path(name).suffix.lower()
    if suffix == ".tif":
        return "image/tiff"
    for mime, extension in MIME_SUFFIXES.items():
        if extension == suffix:
            return mime
    return None


def _next_graphic_filename(header: str) -> tuple[str, int]:
    """Decode an RTF-escaped UTF-8 sibling name and optional twip width."""
    property_match = NEXT_GRAPHIC_PROPERTIES.search(header)
    name_source = header[:property_match.start()] if property_match else header
    raw = bytearray()
    index = 0
    while index < len(name_source):
        char = name_source[index]
        if char == "\\":
            if index + 1 >= len(name_source):
                raise RtfdError("Truncated Apple graphic filename escape")
            next_char = name_source[index + 1]
            if next_char in "{}\\":
                raw.extend(next_char.encode("latin-1"))
                index += 2
            elif next_char == "'" and index + 3 < len(name_source):
                try:
                    raw.append(int(name_source[index + 2:index + 4], 16))
                except ValueError as error:
                    raise RtfdError("Invalid Apple graphic filename escape") from error
                index += 4
            else:
                raise RtfdError("Unsupported Apple graphic filename escape")
        else:
            raw.extend(char.encode("latin-1"))
            index += 1
    try:
        filename = raw.decode("utf-8", errors="strict").strip()
    except UnicodeError as error:
        raise RtfdError("Invalid UTF-8 Apple graphic filename") from error
    if _mime_for_asset(filename) is None:
        raise RtfdError("Apple graphic names must be safe sibling image filenames")
    width_match = re.search(r"\\width([0-9]{1,8})(?![0-9])", header)
    twips = int(width_match.group(1)) if width_match else 4800
    # The stored width grid is 96-960 px, in steps of 16. Twips are 1/1440in.
    width_px = min(960, max(96, (twips * 96 + 720) // 1440))
    width_px = min(960, max(96, ((width_px + 8) // 16) * 16))
    return filename, width_px


def _external_note(
    source: Path, assets: list[Path]
) -> tuple[str, str, dict[str, str]] | None:
    """Resolve only verified AppKit NeXTGraphic siblings to inline image tokens.

    This does not interpret RTF programs or external paths. Apple graphic groups
    become unique private-use placeholders before passing to the existing
    bounded RTF reader, and are then replaced with the app's object character.
    """
    rtf = source / "TXT.rtf"
    descriptor = os.open(rtf, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > _rtf_import.MAX_INPUT_BYTES:
            raise RtfdError("Apple RTFD text is not a bounded regular file")
        raw = stream.read(_rtf_import.MAX_INPUT_BYTES + 1)
        if len(raw) > _rtf_import.MAX_INPUT_BYTES:
            raise RtfdError("Apple RTFD exceeds the bounded text limit")
    data = raw.decode("latin-1")
    found = list(NEXT_GRAPHIC.finditer(data))
    if not found:
        if r"\NeXTGraphic" in data:
            raise RtfdError("Unsupported Apple graphic record")
        return None
    if len(found) > MAX_RTF_GRAPHICS:
        raise RtfdError("RTFD contains too many inline graphics")
    expected = len(re.findall(r"\{\{\\NeXTGraphic\b", data, re.IGNORECASE))
    if expected != len(found):
        raise RtfdError("Malformed or unsupported Apple graphic record")
    by_name = {file.name: file for file in assets}
    identifiers = {
        name: str(uuid.uuid5(uuid.NAMESPACE_URL, "majoris-rtfd:" + name))
        for name in by_name
    }
    blocks: list[str] = []
    position = 0
    assignments: list[tuple[str, int, str]] = []
    for index, match in enumerate(found):
        name, width = _next_graphic_filename(match.group(1))
        if name not in by_name:
            raise RtfdError("Apple graphic references a missing sibling")
        if not ("image/" in (_mime_for_asset(name) or "")):
            raise RtfdError("Inline Apple graphic must be a supported image")
        marker = chr(0xE000 + index)
        blocks.append(data[position:match.start()])
        # Convert private-use marker to an RTF Unicode control, not raw UTF-8.
        blocks.append(r"\uc1\u" + str(ord(marker) - 65536) + "?")
        assignments.append((marker, width, identifiers[name]))
        position = match.end()
    blocks.append(data[position:])
    replacement = "".join(blocks).encode("latin-1")
    body, formatting = _rtf_import.RtfReader().parse(replacement)
    for marker, width, identifier in assignments:
        if body.count(marker) != 1:
            raise RtfdError("Ambiguous inline Apple graphic location")
        start = body.index(marker)
        formatting += f"{start}:{start + 1}:image_{identifier}_{width}\n"
        body = body.replace(marker, "\ufffc", 1)
    if len(formatting.encode("utf-8")) > _rtf_export.MAX_FORMATTING_BYTES:
        raise RtfdError("Apple RTFD formatting exceeds supported size")
    if len(body.encode("utf-8")) > _rtf_export.MAX_NOTE_BYTES:
        raise RtfdError("Apple RTFD text exceeds supported size")
    _rtf_export._spans(body, formatting)
    return body, formatting, identifiers


def inspect_package(source: Path) -> tuple[str, str, list[Path]]:
    """Validate and decode text and safe attachment paths without modifying files."""
    if source.suffix.lower() != ".rtfd" or source.is_symlink() or not source.is_dir():
        raise RtfdError("Select a real .rtfd directory")
    names = list(source.iterdir())
    if len(names) > MAX_ATTACHMENTS + 2:
        raise RtfdError("RTFD directory contains too many entries")
    rtf = source / "TXT.rtf"
    if not rtf in names:
        raise RtfdError("RTFD directory requires TXT.rtf")
    text, formatting = import_rtf(rtf)
    included: list[Path] = []
    total_bytes = _regular_file(rtf, MAX_PACKAGE_BYTES)
    for path in sorted(names):
        if path.name == "TXT.rtf":
            continue
        if path.name == "majoris.json":
            total_bytes += _regular_file(path, MAX_MANIFEST_BYTES)
            _read_manifest(path)
            continue
        mime = _mime_for_asset(path.name)
        if mime is None:
            raise RtfdError("Unsupported or untrusted RTFD attachment filename")
        total_bytes += _regular_file(path, MAX_ATTACHMENT_BYTES)
        if total_bytes > MAX_PACKAGE_BYTES:
            raise RtfdError("RTFD directory exceeds 128 MiB")
        included.append(path)
    if len(included) > MAX_ATTACHMENTS:
        raise RtfdError("RTFD package contains too many attachments")
    read_attachment_metadata(source, included)
    if read_native_note(source, included) is None:
        _external_note(source, included)
    return text, formatting, included



def read_attachment_metadata(source: Path, included: list[Path]) -> dict[str, tuple[str, str]]:
    """Validate optional Majoris metadata against actual package files.

    The manifest never selects a filesystem path: filenames are matched against
    independently validated entries. Untrusted display names cannot contain
    separators, controls, or path traversal components. Legacy packages without
    metadata retain their generated filenames.
    """
    manifest_path = source / "majoris.json"
    if not manifest_path.exists() and not manifest_path.is_symlink():
        return {
            asset.name: (asset.name, _mime_for_asset(asset.name) or "")
            for asset in included
        }
    manifest = _read_manifest(manifest_path)
    entries = manifest.get("attachments")
    if not isinstance(entries, list) or len(entries) != len(included):
        raise RtfdError("RTFD metadata does not match its attachment collection")
    asset_names = {asset.name for asset in included}
    metadata: dict[str, tuple[str, str]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise RtfdError("Invalid RTFD attachment metadata entry")
        filename = entry.get("file")
        name = entry.get("name")
        mime = entry.get("mime")
        if (not isinstance(filename, str) or filename not in asset_names
                or filename in metadata or not isinstance(name, str)
                or not name or name in {".", ".."}
                or len(name.encode("utf-8")) > 255
                or any(char in name for char in "/\\")
                or any(ord(char) < 32 or ord(char) == 127 for char in name)
                or not isinstance(mime, str)
                or mime not in MIME_SUFFIXES
                or not filename.endswith(MIME_SUFFIXES[mime])
                or ("source_id" in entry and
                    (not isinstance(entry["source_id"], str) or
                     not IDENTIFIER.fullmatch(entry["source_id"])))):
            raise RtfdError("Invalid RTFD attachment name, type, or mapping")
        metadata[filename] = (name, mime)
    return metadata

def read_native_note(
    source: Path, included: list[Path]
) -> tuple[str, str, dict[str, str]] | None:
    """Validate the optional lossless Majoris text and inline asset identities.

    Standard TXT.rtf always remains the external interchange fallback. The
    native payload is used only by Majoris when all its references validate.
    """
    manifest_path = source / "majoris.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        return None
    manifest = _read_manifest(manifest_path)
    native = manifest.get("native")
    if native is None:
        return None
    if not isinstance(native, dict) or set(native) != {"content", "formatting"}:
        raise RtfdError("Invalid native note payload")
    text, formatting = native["content"], native["formatting"]
    if not isinstance(text, str) or not isinstance(formatting, str):
        raise RtfdError("RTFD native text is not UTF-8")
    if "\x00" in text or "\x00" in formatting:
        raise RtfdError("RTFD native note contains NUL")
    if (len(text.encode("utf-8")) > _rtf_export.MAX_NOTE_BYTES or
            len(formatting.encode("utf-8")) > _rtf_export.MAX_FORMATTING_BYTES):
        raise RtfdError("Native note payload exceeds the supported size")
    spans = _rtf_export._spans(text, formatting)
    assets_by_file = {entry["file"]: entry for entry in manifest["attachments"]}
    source_ids: dict[str, str] = {}
    for file in included:
        entry = assets_by_file[file.name]
        identity = entry.get("source_id")
        if not isinstance(identity, str) or not IDENTIFIER.fullmatch(identity):
            raise RtfdError("Native RTFD requires stable attachment identifiers")
        if identity in source_ids.values():
            raise RtfdError("Native RTFD contains duplicate attachment identities")
        source_ids[file.name] = identity
    by_id = {identifier: assets_by_file[name] for name, identifier in source_ids.items()}
    for start, end, style in spans:
        if not style.startswith("image_"):
            continue
        match = _rtf_export.re.fullmatch(
            r"image_([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})_([0-9]{2,4})", style
        )
        if (not match or end != start + 1 or text[start:end] != "\uFFFC" or
                match.group(1) not in by_id or
                not by_id[match.group(1)]["mime"].startswith("image/")):
            raise RtfdError("Native inline media does not match the manifest")
    return text, formatting, source_ids


def main(argv: list[str] | None = None) -> int:
    """Expose explicit local export and non-mutating inspect operations."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("data_dir", type=Path)
    export.add_argument("note_id")
    export.add_argument("destination", type=Path)
    inspect = commands.add_parser("inspect")
    inspect.add_argument("source", type=Path)
    metadata = commands.add_parser("metadata")
    metadata.add_argument("source", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            export_note(args.data_dir, args.note_id, args.destination)
        elif args.command == "inspect":
            text, formatting, assets = inspect_package(args.source)
            print(json.dumps({"text": text, "formatting": formatting,
                              "files": [str(path) for path in assets]}, ensure_ascii=True))
        else:
            _, _, assets = inspect_package(args.source)
            descriptions = read_attachment_metadata(args.source, assets)
            native = read_native_note(args.source, assets)
            if native is None:
                native = _external_note(args.source, assets)
            if native is not None:
                text, formatting, identities = native
                print(f"@content\t{quote(text, safe='')}")
                print(f"@formatting\t{quote(formatting, safe='')}")
            else:
                identities = {}
            for asset in assets:
                name, mime = descriptions[asset.name]
                print(f"{asset.name}\t{quote(name, safe='')}\t{mime}\t"
                      f"{identities.get(asset.name, '')}")
    except (OSError, sqlite3.Error, UnicodeError, json.JSONDecodeError,
            RtfdError, RtfImportError, RtfExportError) as error:
        print(f"RTFD failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
