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
import mimetypes
import os
import re
import shutil
import sqlite3
import stat
import sys
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
SAFE_ASSET_NAME = re.compile(r"attachment-[0-9]{4}\.[a-z0-9]{1,8}\Z")
MIME_SUFFIXES = {
    "image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif",
    "image/tiff": ".tiff", "image/webp": ".webp", "image/bmp": ".bmp",
    "application/pdf": ".pdf", "image/svg+xml": ".svg",
    "image/avif": ".avif", "image/heif": ".heif", "image/heic": ".heic",
}


class RtfdError(ValueError):
    """Report a rejected package or failed local interchange operation."""


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
    rendered = make_rtf(*note)
    manifest = {"format": "majoris-rtfd-1", "attachments": []}
    asset_paths: list[tuple[Path, str, int]] = []
    package_bytes = len(rendered)
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
            {"file": name, "name": display_name[:255], "mime": mime}
        )
    try:
        destination.mkdir(mode=0o700)
    except OSError as error:
        raise RtfdError("Cannot create new RTFD directory") from error
    try:
        (destination / "TXT.rtf").write_bytes(rendered)
        (destination / "majoris.json").write_text(
            json.dumps(manifest, ensure_ascii=True, separators=(",", ":")),
            encoding="utf-8",
        )
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
            total_bytes += _regular_file(path, 32 * 1024)
            metadata = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(metadata, dict) or metadata.get("format") != "majoris-rtfd-1":
                raise RtfdError("Unsupported Majoris RTFD manifest")
            continue
        mime, _ = mimetypes.guess_type(path.name)
        if not SAFE_ASSET_NAME.fullmatch(path.name) or (
            mime != "application/pdf" and not (mime or "").startswith("image/")
        ):
            raise RtfdError("Unsupported or untrusted RTFD attachment filename")
        total_bytes += _regular_file(path, MAX_ATTACHMENT_BYTES)
        if total_bytes > MAX_PACKAGE_BYTES:
            raise RtfdError("RTFD directory exceeds 128 MiB")
        included.append(path)
    if len(included) > MAX_ATTACHMENTS:
        raise RtfdError("RTFD package contains too many attachments")
    return text, formatting, included


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
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            export_note(args.data_dir, args.note_id, args.destination)
        else:
            text, formatting, assets = inspect_package(args.source)
            print(json.dumps({"text": text, "formatting": formatting,
                              "files": [str(path) for path in assets]}, ensure_ascii=True))
    except (OSError, sqlite3.Error, UnicodeError, json.JSONDecodeError,
            RtfdError, RtfImportError, RtfExportError) as error:
        print(f"RTFD failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
