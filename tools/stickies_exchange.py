#!/usr/bin/env python3
"""Share individual Stickies notes and explicitly merge a local sync folder.

Folder synchronization is a manual offline operation: close the application
before invoking ``sync --app-closed``. No server, credentials, or polling are
created. Each independent device needs its own database and sync receipt file.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import os
import re
import stat
import sqlite3
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote, urlsplit

BUNDLE_VERSION = 1
SCHEMA_VERSION = 7
TITLE_SCHEMA_VERSION = 6
PREVIOUS_SCHEMA_VERSION = 5
LEGACY_SCHEMA_VERSION = 4
MAX_ASSET_BYTES = 50 * 1024 * 1024
MAX_BUNDLE_BYTES = 256 * 1024 * 1024
MAX_ATTACHMENTS = 128
MAX_NOTE_TEXT = 2 * 1024 * 1024
MAX_STATE_BYTES = 2 * 1024 * 1024
IDENTIFIER = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
INLINE_IMAGE = re.compile(r"image_([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})_([0-9]{2,4})\Z")
RGB_STYLE = re.compile(r"rgb_[0-9a-f]{6}\Z")
POINT_STYLE = re.compile(r"point_([0-9]|[1-9][0-9])\Z")
def default_data_dir() -> Path:
    """Use an absolute XDG_DATA_HOME, falling back to the GLib default."""
    location = os.environ.get("XDG_DATA_HOME", "")
    base = Path(location) if location else Path.home() / ".local/share"
    if not base.is_absolute():
        base = Path.home() / ".local/share"
    return base / "majoris" / "stickies"


DATA_DIR = default_data_dir()
PREVIOUS_NOTE_COLUMNS = (
    "id", "title", "content", "color", "created_at_us", "updated_at_us",
    "formatting", "collapsed", "floating", "translucent", "window_width",
    "window_height", "visible", "source_url", "remind_at_us",
    "reminder_notified_at_us", "status", "pinned",
)
TITLE_NOTE_COLUMNS = PREVIOUS_NOTE_COLUMNS + ("auto_title",)
NOTE_COLUMNS = TITLE_NOTE_COLUMNS + ("reminder_repeat_us",)
LEGACY_NOTE_COLUMNS = PREVIOUS_NOTE_COLUMNS[:-2]


class ExchangeError(Exception):
    """Rejects invalid bundles, unsafe paths and synchronization conflicts."""


def _json_bytes(value: object) -> bytes:
    """Produce deterministic UTF-8 data for portable revision comparison."""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )


def _decode_unique(value: bytes) -> Any:
    """Reject duplicate object keys instead of trusting the last occurrence."""
    def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        """Validate the key set within each nested JSON object."""
        result: dict[str, Any] = {}
        for name, item in pairs:
            if name in result:
                raise ExchangeError("Duplicate JSON field")
            result[name] = item
        return result

    try:
        return json.loads(value.decode("utf-8"), object_pairs_hook=unique_pairs)
    except (ValueError, UnicodeError) as error:
        raise ExchangeError("Invalid JSON in the exchange data") from error


def _sha256(value: bytes) -> str:
    """Return a hex digest for one bounded byte payload."""
    return hashlib.sha256(value).hexdigest()


def _valid_id(value: object) -> bool:
    """Accept only canonical lowercase UUID-form identifiers."""
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def _style_supported(style: str) -> bool:
    """Match the editor's bounded fixed, dynamic, and inline-image style tokens."""
    fixed = {
        "bold", "italic", "underline", "strikethrough", "monospace", "large", "small",
        "font-sans", "font-serif", "font-monospace",
        *(f"size-{point}" for point in (10, 12, 14, 16, 18, 20, 24)),
        "text-red", "text-blue", "text-green", "align-left", "align-center",
        "align-right", "list-bullet", "list-numbered", "list-checklist",
        *(f"list-depth-{depth}" for depth in range(1, 7)),
    }
    if style in fixed or RGB_STYLE.fullmatch(style):
        return True
    image = INLINE_IMAGE.fullmatch(style)
    if image:
        width = int(image.group(2))
        return 96 <= width <= 960 and width % 16 == 0 and style.endswith(f"_{width}")
    match = POINT_STYLE.fullmatch(style)
    if match:
        return 8 <= int(match.group(1)) <= 72 and style == f"point_{int(match.group(1))}"
    if style.startswith("face_") and len(style) <= 240:
        try:
            family = unquote(style[5:], encoding="utf-8", errors="strict")
        except UnicodeError:
            return False
        return (bool(family) and len(family.encode("utf-8")) <= 96 and
                all(ord(char) >= 32 and char != "\x7f" and char not in ":\\"
                    for char in family) and
                quote(family, safe="") == style[5:])
    return False


def _image_references(note: dict[str, Any]) -> set[str]:
    """Validate object-character placement and collect referenced image identities."""
    references: set[str] = set()
    for line in note["formatting"].splitlines():
        if not line:
            continue
        start_text, end_text, style = line.split(":")
        match = INLINE_IMAGE.fullmatch(style)
        if match:
            start, end = int(start_text), int(end_text)
            if end != start + 1 or note["content"][start:end] != "\uFFFC":
                raise ExchangeError("Inline-image span must cover one object character")
            references.add(match.group(1))
    return references


def _verify_image_references(
    note: dict[str, Any], assets: dict[str, tuple[dict[str, str], bytes]]
) -> None:
    """Require every inline image to belong to this verified note's image assets."""
    for identity in _image_references(note):
        if identity not in assets or not assets[identity][0]["mime"].startswith("image/"):
            raise ExchangeError("Inline image references an absent or non-image attachment")


def _remap_inline_formatting(formatting: str, identities: dict[str, str]) -> str:
    """Change only validated inline-image identities, retaining all other spans."""
    lines = []
    for line in formatting.split("\n"):
        fields = line.split(":")
        if len(fields) == 3:
            match = INLINE_IMAGE.fullmatch(fields[2])
            if match and match.group(1) in identities:
                fields[2] = f"image_{identities[match.group(1)]}_{match.group(2)}"
                line = ":".join(fields)
        lines.append(line)
    return "\n".join(lines)


def _portable_formatting(formatting: str, records: list[dict[str, str]]) -> str:
    """Hash portable media content, not machine-specific attachment UUIDs."""
    hashes = {record["id"]: record["sha256"] for record in records}
    return _remap_inline_formatting(formatting, hashes)


def _validate_note(note: object) -> dict[str, Any]:
    """Check a remote record before any database or filesystem mutation."""
    if not isinstance(note, dict) or set(note) not in (
        set(NOTE_COLUMNS), set(TITLE_NOTE_COLUMNS),
        set(PREVIOUS_NOTE_COLUMNS), set(LEGACY_NOTE_COLUMNS)
    ):
        raise ExchangeError("Unexpected note record fields")
    note = dict(note)
    note.setdefault("status", 0)
    note.setdefault("pinned", 0)
    note.setdefault("auto_title", 0)
    note.setdefault("reminder_repeat_us", 0)
    if not _valid_id(note["id"]):
        raise ExchangeError("Invalid note identifier")
    for field in ("title", "content", "formatting", "color", "source_url"):
        if not isinstance(note[field], str):
            raise ExchangeError(f"Invalid {field} data")
    palette = {"yellow", "pink", "green", "blue", "purple", "orange", "teal", "gray"}
    custom = re.fullmatch(r"#[0-9a-f]{6}", note["color"])
    if custom:
        red, green, blue = (int(note["color"][start:start + 2], 16)
                            for start in (1, 3, 5))
        custom = (red * 2126 + green * 7152 + blue * 722 >= 180 * 10000)
    if len(note["title"]) > 160 or not (note["color"] in palette or custom):
        raise ExchangeError("Invalid title or paper color")
    formatting = note["formatting"]
    if len(formatting.encode("utf-8")) > 1048576:
        raise ExchangeError("Formatting exceeds the supported size")
    if len(formatting.splitlines()) > 20000:
        raise ExchangeError("Too many formatting spans")
    for line in formatting.splitlines():
        if not line:
            continue
        fields = line.split(":")
        if len(fields) != 3 or not _style_supported(fields[2]) or not all(
            item.isascii() and item.isdecimal() for item in fields[:2]
        ):
            raise ExchangeError("Invalid note formatting")
        start, end = int(fields[0]), int(fields[1])
        if start < 0 or end <= start or end > len(note["content"]):
            raise ExchangeError("Invalid note formatting range")
    if len(_json_bytes(note)) > MAX_NOTE_TEXT:
        raise ExchangeError("Note text is too large to exchange")
    for name in ("created_at_us", "updated_at_us", "remind_at_us", "reminder_notified_at_us",
                 "reminder_repeat_us"):
        if type(note[name]) is not int or note[name] < 0:
            raise ExchangeError(f"Invalid {name}")
    if note["reminder_repeat_us"] not in (0, 86_400_000_000, 604_800_000_000):
        raise ExchangeError("Invalid reminder recurrence")
    if note["remind_at_us"] == 0 and note["reminder_repeat_us"] != 0:
        raise ExchangeError("A cleared reminder cannot recur")
    for name in ("collapsed", "floating", "translucent", "visible", "pinned", "auto_title"):
        if type(note[name]) is not int or note[name] not in (0, 1):
            raise ExchangeError(f"Invalid {name}")
    if not all(type(note[name]) is int and 120 <= note[name] <= 4000 for name in
               ("window_width", "window_height")):
        raise ExchangeError("Invalid window geometry")
    if type(note["status"]) is not int or note["status"] not in (0, 1, 2):
        raise ExchangeError("Invalid note lifecycle state")
    url = note["source_url"]
    if url:
        if len(url.encode("utf-8")) > 2048 or any(ord(char) < 32 for char in url):
            raise ExchangeError("Unsafe source URL")
        try:
            parsed = urlsplit(url)
            if (parsed.scheme not in ("http", "https") or not parsed.hostname or
                    parsed.username is not None or parsed.password is not None):
                raise ValueError("unsupported URL")
        except ValueError as error:
            raise ExchangeError("Unsafe source URL") from error
    return note


def _check_source_file(path: Path, limit: int) -> None:
    """Require a regular non-symlink filesystem input within the size limit."""
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise ExchangeError(f"Unsafe, missing, or oversized file: {path.name}")


def _snapshot(data_dir: Path) -> tuple[sqlite3.Connection, Path]:
    """Take an SQLite-consistent in-memory snapshot for sharing or comparing."""
    database_path = data_dir / "notes.db"
    _check_source_file(database_path, MAX_BUNDLE_BYTES)
    disk = sqlite3.connect(database_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=3)
    snapshot = sqlite3.connect(":memory:")
    try:
        disk.backup(snapshot, pages=256, sleep=0.05)
    finally:
        disk.close()
    snapshot.row_factory = sqlite3.Row
    if snapshot.execute("PRAGMA quick_check(1)").fetchone()[0] != "ok":
        snapshot.close()
        raise ExchangeError("Damaged SQLite database")
    version = snapshot.execute("PRAGMA user_version").fetchone()[0]
    if version not in (
        LEGACY_SCHEMA_VERSION, PREVIOUS_SCHEMA_VERSION,
        TITLE_SCHEMA_VERSION, SCHEMA_VERSION,
    ):
        snapshot.close()
        raise ExchangeError("Open the current Stickies application to migrate this database")
    return snapshot, database_path


def _note_records(connection: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    """Return an ID-indexed, validated snapshot of local note records."""
    schema = connection.execute("PRAGMA user_version").fetchone()[0]
    columns = (NOTE_COLUMNS if schema == SCHEMA_VERSION else
               TITLE_NOTE_COLUMNS if schema == TITLE_SCHEMA_VERSION else
               PREVIOUS_NOTE_COLUMNS if schema == PREVIOUS_SCHEMA_VERSION else
               LEGACY_NOTE_COLUMNS)
    return {
        row["id"]: _validate_note(dict(row))
        for row in connection.execute(f"SELECT {','.join(columns)} FROM notes")
    }


def _assets_for_note(
    connection: sqlite3.Connection, data_dir: Path, note_id: str
) -> dict[str, tuple[dict[str, str], bytes]]:
    """Load a note's permitted attachments and verify their size and identity."""
    assets: dict[str, tuple[dict[str, str], bytes]] = {}
    query = "SELECT id,display_name,mime_type FROM attachments WHERE note_id=? ORDER BY id"
    for row in connection.execute(query, (note_id,)):
        identifier, display_name, mime_type = row
        if not _valid_id(identifier) or len(assets) >= MAX_ATTACHMENTS:
            raise ExchangeError("Invalid attachment identity or too many attachments")
        path = data_dir / "attachments" / f"{identifier}.asset"
        _check_source_file(path, MAX_ASSET_BYTES)
        content = path.read_bytes()
        if (not isinstance(display_name, str) or len(display_name) > 255 or
                not isinstance(mime_type, str) or len(mime_type) > 128):
            raise ExchangeError("Invalid attachment metadata")
        assets[identifier] = (
            {"id": identifier, "name": display_name, "mime": mime_type,
             "sha256": _sha256(content)},
            content,
        )
    return assets


def _revision(note: dict[str, Any], records: list[dict[str, str]]) -> str:
    """Compare portable content without machine-local window or delivery state."""
    shared_fields = (
        "id", "title", "content", "color", "created_at_us", "updated_at_us",
        "formatting", "source_url", "remind_at_us", "status", "pinned",
        "auto_title", "reminder_repeat_us",
    )
    # Attachment IDs are local storage keys and legitimately change on import.
    portable_assets = sorted(
        ({"name": entry["name"], "mime": entry["mime"], "sha256": entry["sha256"]}
         for entry in records),
        key=lambda value: (value["name"], value["mime"], value["sha256"]),
    )
    return _sha256(_json_bytes({
        "note": {name: (_portable_formatting(note[name], records) if name == "formatting"
                         else note[name]) for name in shared_fields}, "assets": portable_assets,
    }))


def _title_revision(note: dict[str, Any], entries: list[dict[str, str]]) -> str:
    """Verify earlier schema-v6 bundles without inventing recurrence fields."""
    fields = (
        "id", "title", "content", "color", "created_at_us", "updated_at_us",
        "formatting", "source_url", "remind_at_us", "status", "pinned", "auto_title",
    )
    portable_assets = sorted(
        ({"name": entry["name"], "mime": entry["mime"], "sha256": entry["sha256"]}
         for entry in entries),
        key=lambda value: (value["name"], value["mime"], value["sha256"]),
    )
    return _sha256(_json_bytes({
        "note": {name: (_portable_formatting(note[name], entries) if name == "formatting"
                         else note[name]) for name in fields}, "assets": portable_assets,
    }))


def _previous_revision(note: dict[str, Any], entries: list[dict[str, str]]) -> str:
    """Validate pre-v6 bundle signatures without implicit title-mode state."""
    previous_fields = (
        "id", "title", "content", "color", "created_at_us", "updated_at_us",
        "formatting", "source_url", "remind_at_us", "status", "pinned",
    )
    portable_assets = sorted(
        ({"name": entry["name"], "mime": entry["mime"], "sha256": entry["sha256"]}
         for entry in entries),
        key=lambda value: (value["name"], value["mime"], value["sha256"]),
    )
    return _sha256(_json_bytes({
        "note": {key: (_portable_formatting(note[key], entries) if key == "formatting"
                       else note[key]) for key in previous_fields},
        "assets": portable_assets,
    }))


def _legacy_revision(note: dict[str, Any], entries: list[dict[str, str]]) -> str:
    """Verify the v0.5 portable content identity for unchanged active notes."""
    legacy_fields = (
        "id", "title", "content", "color", "created_at_us", "updated_at_us",
        "formatting", "source_url", "remind_at_us",
    )
    portable_assets = sorted(
        ({"name": entry["name"], "mime": entry["mime"],
          "sha256": entry["sha256"]} for entry in entries),
        key=lambda value: (value["name"], value["mime"], value["sha256"]),
    )
    return _sha256(_json_bytes({
        "note": {key: (_portable_formatting(note[key], entries) if key == "formatting"
                         else note[key]) for key in legacy_fields},
        "assets": portable_assets,
    }))


def _pack_note(
    note: dict[str, Any], assets: dict[str, tuple[dict[str, str], bytes]]
) -> tuple[bytes, str]:
    """Create a bounded, deterministic single-note ZIP with verified assets."""
    _verify_image_references(note, assets)
    records = [assets[key][0] for key in sorted(assets)]
    legacy = (not note["auto_title"] and not note["reminder_repeat_us"] and
              note["status"] == 0 and note["pinned"] == 0)
    previous = (not note["auto_title"] and not note["reminder_repeat_us"] and
                not legacy)
    title = not note["reminder_repeat_us"] and not legacy and not previous
    revision = (_legacy_revision(note, records) if legacy else
                _previous_revision(note, records) if previous else
                _title_revision(note, records) if title else _revision(note, records))
    transferable_note = (
        {field: note[field] for field in LEGACY_NOTE_COLUMNS} if legacy else
        {field: note[field] for field in PREVIOUS_NOTE_COLUMNS} if previous else
        {field: note[field] for field in TITLE_NOTE_COLUMNS} if title else note
    )
    manifest = {
        "format": "majoris-stickies-note", "version": BUNDLE_VERSION,
        "note": transferable_note, "assets": records, "revision": revision,
    }
    with io.BytesIO() as output:
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("manifest.json", _json_bytes(manifest))
            for identifier in sorted(assets):
                archive.writestr(f"assets/{identifier}.asset", assets[identifier][1])
        payload = output.getvalue()
    if len(payload) > MAX_BUNDLE_BYTES:
        raise ExchangeError("The shared note exceeds the bundle size limit")
    return payload, revision


def _read_bundle(path: Path) -> tuple[dict[str, Any], dict[str, tuple[dict[str, str], bytes]], str]:
    """Fully validate a note bundle before exposing its records or files."""
    _check_source_file(path, MAX_BUNDLE_BYTES)
    assets: dict[str, tuple[dict[str, str], bytes]] = {}
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or len(names) > MAX_ATTACHMENTS + 1:
                raise ExchangeError("Duplicate or excessive archive entries")
            if "manifest.json" not in names:
                raise ExchangeError("Missing share manifest")
            metadata = archive.getinfo("manifest.json")
            if metadata.file_size > MAX_NOTE_TEXT:
                raise ExchangeError("Oversized share manifest")
            manifest = _decode_unique(archive.read("manifest.json"))
            if not isinstance(manifest, dict) or set(manifest) != {
                "format", "version", "note", "assets", "revision"
            } or manifest["format"] != "majoris-stickies-note" or manifest["version"] != 1:
                raise ExchangeError("Unsupported note bundle")
            record_fields = set(manifest["note"]) if isinstance(manifest["note"], dict) else set()
            note = _validate_note(manifest["note"])
            entries = manifest["assets"]
            if not isinstance(entries, list) or len(entries) > MAX_ATTACHMENTS:
                raise ExchangeError("Invalid share attachment catalog")
            expected = {"manifest.json"}
            total_bytes = 0
            for entry in entries:
                if not isinstance(entry, dict) or set(entry) != {"id", "name", "mime", "sha256"}:
                    raise ExchangeError("Invalid share attachment record")
                identifier = entry["id"]
                if (not _valid_id(identifier) or not isinstance(entry["name"], str) or
                        len(entry["name"]) > 255 or not isinstance(entry["mime"], str) or
                        len(entry["mime"]) > 128 or not isinstance(entry["sha256"], str) or
                        not SHA256.fullmatch(entry["sha256"])):
                    raise ExchangeError("Invalid share attachment metadata")
                name = f"assets/{identifier}.asset"
                expected.add(name)
                member = archive.getinfo(name)
                if member.file_size > MAX_ASSET_BYTES or member.file_size < 0:
                    raise ExchangeError("Oversized shared asset")
                content = archive.read(name)
                total_bytes += len(content)
                if total_bytes > MAX_BUNDLE_BYTES or _sha256(content) != entry["sha256"]:
                    raise ExchangeError("Shared asset failed SHA-256 validation")
                assets[identifier] = (entry, content)
            if set(names) != expected or len(assets) != len(entries):
                raise ExchangeError("Unexpected file in shared bundle")
            for member in archive.infolist():
                if (member.flag_bits & 1) or (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ExchangeError("Encrypted or symlink archive members are not permitted")
            _verify_image_references(note, assets)
            if record_fields == set(NOTE_COLUMNS):
                revision = _revision(note, entries)
            elif record_fields == set(TITLE_NOTE_COLUMNS):
                revision = _title_revision(note, entries)
            elif record_fields == set(PREVIOUS_NOTE_COLUMNS):
                revision = _previous_revision(note, entries)
            else:
                revision = _legacy_revision(note, entries)
            if revision != manifest["revision"]:
                raise ExchangeError("Share manifest was modified")
            if not isinstance(manifest["revision"], str) or not SHA256.fullmatch(
                manifest["revision"]
            ):
                raise ExchangeError("Invalid share revision")
            return note, assets, manifest["revision"]
    except (KeyError, zipfile.BadZipFile, OSError, ValueError) as error:
        raise ExchangeError("Unreadable or invalid note bundle") from error


def _tombstone_payload(note_id: str, previous: str) -> bytes:
    """Describe one explicitly confirmed deletion without transferring note content."""
    if not _valid_id(note_id) or not SHA256.fullmatch(previous):
        raise ExchangeError("Invalid deletion identity or last-agreed revision")
    return _json_bytes({
        "format": "majoris-stickies-deletion", "version": 1,
        "id": note_id, "previous": previous,
    })


def _read_tombstone(path: Path) -> tuple[str, str, str]:
    """Validate a bounded, regular tombstone and its matching filename."""
    if not _valid_id(path.stem) or path.suffix != ".deleted":
        raise ExchangeError("Unexpected deletion record filename")
    _check_source_file(path, 1024)
    raw = path.read_bytes()
    entry = _decode_unique(raw)
    if (not isinstance(entry, dict) or set(entry) != {
            "format", "version", "id", "previous"} or
            entry["format"] != "majoris-stickies-deletion" or
            type(entry["version"]) is not int or entry["version"] != 1 or
            entry["id"] != path.stem or not isinstance(entry["previous"], str) or
            not SHA256.fullmatch(entry["previous"])):
        raise ExchangeError("Invalid synchronization tombstone")
    return entry["id"], entry["previous"], _sha256(_tombstone_payload(
        entry["id"], entry["previous"]
    ))


def _atomic_write(path: Path, contents: bytes, *, replace: bool = True) -> None:
    """Commit private output atomically, optionally refusing an existing name."""
    descriptor, temporary = tempfile.mkstemp(prefix=".stickies-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        if replace:
            os.replace(temporary, path)
        else:
            # A hard link provides an atomic no-clobber commit on one filesystem.
            os.link(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _load_receipts(data_dir: Path) -> dict[str, str]:
    """Load last-agreed hashes, rejecting an invalid or manipulated state file."""
    path = data_dir / "sync-state.json"
    if not path.exists() and not path.is_symlink():
        return {}
    _check_source_file(path, MAX_STATE_BYTES)
    state = _decode_unique(path.read_bytes())
    if not isinstance(state, dict) or state.get("version") != 1:
        raise ExchangeError("Invalid synchronization receipt version")
    receipts = state.get("revisions")
    if not isinstance(receipts, dict) or any(
        not _valid_id(key) or not isinstance(value, str) or not SHA256.fullmatch(value)
        for key, value in receipts.items()
    ):
        raise ExchangeError("Invalid synchronization receipts")
    return receipts


def _apply_remote(
    connection: sqlite3.Connection, data_dir: Path, note: dict[str, Any],
    assets: dict[str, tuple[dict[str, str], bytes]],
    *, override_id: str | None = None, conflict_copy: bool = False
) -> list[Path]:
    """Stage assets before inserting an imported note and its attachment records."""
    record = dict(note)
    if override_id is not None:
        record["id"] = override_id
    if conflict_copy:
        record["title"] = ("Conflict copy — " + record["title"])[:160]
        record["auto_title"] = 0
        record["updated_at_us"] += 1
    record["visible"] = 0  # Never open another machine's windows unexpectedly.
    _verify_image_references(record, assets)
    new_asset_ids = {identity: str(uuid.uuid4()) for identity in assets}
    record["formatting"] = _remap_inline_formatting(record["formatting"], new_asset_ids)
    stored: list[Path] = []
    if (data_dir / "attachments").is_symlink():
        raise ExchangeError("Attachment directory must not be a symbolic link")
    (data_dir / "attachments").mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        schema = connection.execute("PRAGMA user_version").fetchone()[0]
        if schema == LEGACY_SCHEMA_VERSION and (record["status"] or record["pinned"]):
            raise ExchangeError("Upgrade Stickies to import archived or pinned notes")
        if schema < TITLE_SCHEMA_VERSION and record["auto_title"]:
            raise ExchangeError("Upgrade Stickies to preserve automatic note titles")
        if schema < SCHEMA_VERSION and record["reminder_repeat_us"]:
            raise ExchangeError("Upgrade Stickies to preserve recurring reminders")
        columns = (NOTE_COLUMNS if schema == SCHEMA_VERSION else
               TITLE_NOTE_COLUMNS if schema == TITLE_SCHEMA_VERSION else
               PREVIOUS_NOTE_COLUMNS if schema == PREVIOUS_SCHEMA_VERSION else
               LEGACY_NOTE_COLUMNS)
        fields = ",".join(columns)
        placeholders = ",".join("?" for _ in columns)
        connection.execute(
            f"INSERT INTO notes({fields}) VALUES({placeholders})",
            tuple(record[field] for field in columns),
        )
        for old_id, (entry, content) in assets.items():
            new_id = new_asset_ids[old_id]
            path = data_dir / "attachments" / f"{new_id}.asset"
            if path.exists() or path.is_symlink():
                raise ExchangeError("Generated attachment path already exists")
            _atomic_write(path, content)
            stored.append(path)
            connection.execute(
                "INSERT INTO attachments(id,note_id,display_name,mime_type) VALUES(?,?,?,?)",
                (new_id, record["id"], entry["name"], entry["mime"]),
            )
        return stored
    except Exception:
        for path in stored:
            path.unlink(missing_ok=True)
        raise


def _replace_note(
    connection: sqlite3.Connection, data_dir: Path, note: dict[str, Any],
    assets: dict[str, tuple[dict[str, str], bytes]]
) -> tuple[list[Path], list[Path]]:
    """Replace a local note transactionally, preserving old files until commit."""
    previous = [
        data_dir / "attachments" / f"{row[0]}.asset"
        for row in connection.execute("SELECT id FROM attachments WHERE note_id=?", (note["id"],))
    ]
    connection.execute("DELETE FROM notes WHERE id=?", (note["id"],))
    new_files = _apply_remote(connection, data_dir, note, assets)
    return new_files, previous


def _application_is_running() -> bool:
    """Ask the session bus whether the single-instance Stickies app is active."""
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return False
    try:
        result = subprocess.run(
            ["dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.DBus",
             "/org/freedesktop/DBus", "org.freedesktop.DBus.NameHasOwner",
             "string:com.majoris.stickies"],
            capture_output=True, text=True, check=True, timeout=3,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ExchangeError("Could not verify Stickies application state") from error
    return "boolean true" in result.stdout


def _sync_folder_unlocked(
    data_dir: Path, folder: Path, app_closed: bool, propagate_deletions: bool = False
) -> dict[str, int]:
    """Merge one folder while its advisory lock remains held by the caller."""
    if not app_closed:
        raise ExchangeError("Close Stickies first, then confirm with --app-closed")
    if _application_is_running():
        raise ExchangeError("Stickies is still running; close it before synchronization")
    if (folder.is_symlink() or not folder.is_dir() or data_dir.is_symlink() or
            not data_dir.is_dir()):
        raise ExchangeError("Select existing, real data and synchronization directories")
    receipts = _load_receipts(data_dir)
    snapshot, database_path = _snapshot(data_dir)
    originals = _note_records(snapshot)
    remote: dict[str, tuple[dict[str, Any], dict[str, tuple[dict[str, str], bytes]], str]] = {}
    tombstones: dict[str, tuple[str, str]] = {}
    try:
        for path in sorted(folder.glob("*.deleted")):
            if not propagate_deletions:
                raise ExchangeError(
                    "Folder contains deletion records; confirm with --propagate-deletions"
                )
            identifier, base, digest = _read_tombstone(path)
            tombstones[identifier] = (base, digest)
        for path in sorted(folder.glob("*.stickies")):
            identifier = path.stem
            if not _valid_id(identifier):
                raise ExchangeError("Unexpected shared note filename")
            record = _read_bundle(path)
            if record[0]["id"] != identifier:
                raise ExchangeError("Shared filename does not match note identity")
            remote[identifier] = record
            if identifier in tombstones and tombstones[identifier][0] != record[2]:
                raise ExchangeError("Deletion record conflicts with a newer remote note")
        outgoing: dict[str, tuple[bytes, str]] = {}
        for identifier, note in originals.items():
            assets = _assets_for_note(snapshot, data_dir, identifier)
            outgoing[identifier] = _pack_note(note, assets)
    finally:
        snapshot.close()
    live = sqlite3.connect(database_path.resolve().as_uri() + "?mode=rw", uri=True, timeout=3)
    written: list[Path] = []
    obsolete: list[Path] = []
    totals = {"published": 0, "received": 0, "conflicts": 0,
              "unchanged": 0, "deleted": 0}
    publish_tombstones: list[tuple[Path, bytes]] = []
    remove_shared_bundles: list[Path] = []
    try:
        if live.execute("PRAGMA user_version").fetchone()[0] not in (
            LEGACY_SCHEMA_VERSION, PREVIOUS_SCHEMA_VERSION,
            TITLE_SCHEMA_VERSION, SCHEMA_VERSION
        ):
            raise ExchangeError("Local notes schema changed during synchronization")
        live.execute("PRAGMA foreign_keys=ON")
        live.execute("BEGIN IMMEDIATE")
        for identifier in sorted(set(outgoing) | set(remote) | set(tombstones)):
            shared = remote.get(identifier)
            local = outgoing.get(identifier)
            previous = receipts.get(identifier)
            deletion = tombstones.get(identifier)
            if deletion is not None:
                if local is not None:
                    if not propagate_deletions:
                        raise ExchangeError("Remote deletion requires explicit confirmation")
                    if local[1] != deletion[0]:
                        # Keep all divergent local work as a separately owned note.
                        # The local bundle is authoritative for the conflict copy.
                        temp = data_dir / f".stickies-conflict-{uuid.uuid4()}.stickies"
                        try:
                            _atomic_write(temp, local[0])
                            conflict_note, conflict_assets, _ = _read_bundle(temp)
                        finally:
                            temp.unlink(missing_ok=True)
                        written.extend(_apply_remote(
                            live, data_dir, conflict_note, conflict_assets,
                            override_id=str(uuid.uuid4()), conflict_copy=True,
                        ))
                        totals["conflicts"] += 1
                    obsolete.extend(
                        data_dir / "attachments" / f"{row[0]}.asset"
                        for row in live.execute(
                            "SELECT id FROM attachments WHERE note_id=?", (identifier,)
                        )
                    )
                    live.execute("DELETE FROM notes WHERE id=?", (identifier,))
                    totals["deleted"] += 1
                receipts[identifier] = deletion[1]
                if shared is not None:
                    remove_shared_bundles.append(folder / f"{identifier}.stickies")
                continue
            if shared is not None and local is None and previous is not None and \
                    previous == shared[2] and propagate_deletions:
                # A note was removed locally since the last successful receipt.
                payload = _tombstone_payload(identifier, previous)
                publish_tombstones.append((folder / f"{identifier}.deleted", payload))
                remove_shared_bundles.append(folder / f"{identifier}.stickies")
                receipts[identifier] = _sha256(payload)
                totals["deleted"] += 1
                continue
            if shared is not None and local is None and previous is not None and \
                    propagate_deletions and previous != shared[2]:
                raise ExchangeError(
                    "Local deletion and remote edit conflict; resolve the note manually"
                )
            if shared is None and local is not None:
                _atomic_write(folder / f"{identifier}.stickies", local[0])
                receipts[identifier] = local[1]
                totals["published"] += 1
            elif local is None and shared is not None:
                written.extend(_apply_remote(live, data_dir, shared[0], shared[1]))
                receipts[identifier] = shared[2]
                totals["received"] += 1
            elif shared is not None and local is not None:
                if local[1] == shared[2]:
                    receipts[identifier] = local[1]
                    totals["unchanged"] += 1
                elif previous == local[1]:
                    new_files, old_files = _replace_note(live, data_dir, shared[0], shared[1])
                    written.extend(new_files)
                    obsolete.extend(old_files)
                    receipts[identifier] = shared[2]
                    totals["received"] += 1
                elif previous == shared[2]:
                    _atomic_write(folder / f"{identifier}.stickies", local[0])
                    receipts[identifier] = local[1]
                    totals["published"] += 1
                else:
                    # Both sides changed, or first contact: preserve a distinct
                    # local copy and receive the remote identity as authoritative.
                    # Read local attachment payloads from the already produced bundle.
                    temp = data_dir / f".stickies-conflict-{uuid.uuid4()}.stickies"
                    try:
                        _atomic_write(temp, local[0])
                        copy_note, copy_assets, _ = _read_bundle(temp)
                    finally:
                        temp.unlink(missing_ok=True)
                    written.extend(_apply_remote(
                        live, data_dir, copy_note, copy_assets,
                        override_id=str(uuid.uuid4()), conflict_copy=True,
                    ))
                    new_files, old_files = _replace_note(live, data_dir, shared[0], shared[1])
                    written.extend(new_files)
                    obsolete.extend(old_files)
                    receipts[identifier] = shared[2]
                    totals["conflicts"] += 1
        live.commit()
    except Exception:
        live.rollback()
        for path in written:
            path.unlink(missing_ok=True)
        raise
    finally:
        live.close()
    for path, payload in publish_tombstones:
        _atomic_write(path, payload, replace=False)
    for path in remove_shared_bundles:
        # Remote files were validated before mutation; the folder lock is held.
        path.unlink(missing_ok=True)
    for path in obsolete:
        path.unlink(missing_ok=True)
    _atomic_write(data_dir / "sync-state.json", _json_bytes({"version": 1, "revisions": receipts}))
    return totals


@contextmanager
def exclusive_store_lock(data_dir: Path):
    """Exclude GUI startup and other mutating exchange operations until exit.

    This shares the .stickies-session.lock flock protocol with the native app.
    Merely checking D-Bus before editing cannot prevent startup during sync.
    """
    try:
        info = data_dir.lstat()
    except OSError as error:
        raise ExchangeError("The Stickies data directory is unavailable") from error
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise ExchangeError("Stickies requires a real user-owned data directory")
    flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        descriptor = os.open(data_dir / ".stickies-session.lock", flags, 0o600)
    except OSError as error:
        raise ExchangeError("Could not safely open the notes session lock") from error
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                info.st_nlink != 1 or info.st_mode & 0o077):
            raise ExchangeError("Notes session lock must be an owner-only regular file")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ExchangeError("Stickies is open or another import/sync is running") from error
        yield
    finally:
        os.close(descriptor)


def sync_folder(
    data_dir: Path, folder: Path, app_closed: bool, propagate_deletions: bool = False
) -> dict[str, int]:
    """Serialize local sync operations with a non-symlink advisory folder lock."""
    if not app_closed:
        raise ExchangeError("Close Stickies first, then confirm with --app-closed")
    if folder.is_symlink() or not folder.is_dir():
        raise ExchangeError("Synchronization folder must be an existing directory")
    flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        descriptor = os.open(folder / ".stickies-sync.lock", flags, 0o600)
    except OSError as error:
        raise ExchangeError("Could not safely open the folder lock") from error
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ExchangeError("Another folder synchronization is running") from error
        with exclusive_store_lock(data_dir):
            return _sync_folder_unlocked(
                data_dir, folder, app_closed, propagate_deletions
            )
    finally:
        os.close(descriptor)


def share_note(data_dir: Path, note_id: str, output: Path) -> None:
    """Create one privacy-scoped, attachment-inclusive note bundle."""
    if not _valid_id(note_id):
        raise ExchangeError("Invalid note ID")
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ExchangeError("Share destination must not already exist")
    snapshot, _ = _snapshot(data_dir)
    try:
        note = _note_records(snapshot).get(note_id)
        if note is None:
            raise ExchangeError("The requested note was not found")
        payload, _ = _pack_note(note, _assets_for_note(snapshot, data_dir, note_id))
    finally:
        snapshot.close()
    _atomic_write(output, payload, replace=False)


def import_note(data_dir: Path, source: Path, app_closed: bool) -> str:
    """Import a verified bundle without racing GUI startup or another import."""
    if not app_closed:
        raise ExchangeError("Close Stickies first, then confirm with --app-closed")
    with exclusive_store_lock(data_dir):
        return _import_note_unlocked(data_dir, source, app_closed)


def _import_note_unlocked(data_dir: Path, source: Path, app_closed: bool) -> str:
    """Perform a verified one-note import while the notes-store lock is held."""
    if not app_closed:
        raise ExchangeError("Close Stickies first, then confirm with --app-closed")
    if _application_is_running():
        raise ExchangeError("Stickies is still running; close it before importing")
    note, assets, revision = _read_bundle(source)
    snapshot, database_path = _snapshot(data_dir)
    try:
        local = _note_records(snapshot).get(note["id"])
        if local is not None:
            _, local_revision = _pack_note(
                local, _assets_for_note(snapshot, data_dir, note["id"])
            )
            if local_revision == revision:
                return "Note already present"
    finally:
        snapshot.close()
    connection = sqlite3.connect(database_path.resolve().as_uri() + "?mode=rw", uri=True)
    written: list[Path] = []
    try:
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("BEGIN IMMEDIATE")
        collision = connection.execute(
            "SELECT 1 FROM notes WHERE id=?", (note["id"],)
        ).fetchone() is not None
        written = _apply_remote(
            connection, data_dir, note, assets,
            override_id=str(uuid.uuid4()) if collision else None,
            conflict_copy=collision,
        )
        connection.commit()
        return "Imported as a new conflict copy" if collision else "Note imported"
    except Exception:
        connection.rollback()
        for path in written:
            path.unlink(missing_ok=True)
        raise
    finally:
        connection.close()


def main(argv: list[str] | None = None) -> int:
    """Dispatch explicit share and offline folder-sync commands."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="List note IDs for optional sharing")
    share = commands.add_parser("share", help="Share one note plus its attachments")
    share.add_argument("note_id")
    share.add_argument("destination", type=Path)
    receiving = commands.add_parser("import", help="Receive a previously shared note")
    receiving.add_argument("source", type=Path)
    receiving.add_argument("--app-closed", action="store_true")
    sync = commands.add_parser(
        "sync", help="Merge a shared folder; Stickies must be closed"
    )
    sync.add_argument("folder", type=Path)
    sync.add_argument("--app-closed", action="store_true", help="Confirm that Stickies is closed")
    sync.add_argument(
        "--propagate-deletions", action="store_true",
        help="Explicitly publish and receive permanent note deletions"
    )
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "list":
            snapshot, _ = _snapshot(arguments.data_dir)
            try:
                for note in sorted(_note_records(snapshot).values(), key=lambda item: item["id"]):
                    title = " ".join(note["title"].split())
                    print(f"{note['id']}  {title}")
            finally:
                snapshot.close()
        elif arguments.command == "share":
            share_note(arguments.data_dir, arguments.note_id, arguments.destination)
            print("Single-note bundle created")
        elif arguments.command == "import":
            print(import_note(arguments.data_dir, arguments.source, arguments.app_closed))
        else:
            result = sync_folder(
                arguments.data_dir, arguments.folder, arguments.app_closed,
                arguments.propagate_deletions
            )
            print("Synchronized: " + ", ".join(f"{key}={value}" for key, value in result.items()))
        return 0
    except (ExchangeError, OSError, sqlite3.Error) as error:
        print(f"Exchange failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
