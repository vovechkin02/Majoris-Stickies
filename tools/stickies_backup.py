#!/usr/bin/env python3
"""Create, verify, and safely restore offline Majoris Stickies backup archives.

Run restore only while Stickies is closed. Restoration creates a new directory;
never replace the active application data directory while the app is running.
"""

from __future__ import annotations

from contextlib import closing

import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import stat
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import BinaryIO
from urllib.parse import quote

ARCHIVE_VERSION = 1
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024
MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024
MAX_FILES = 10_000
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_LAYOUT_BYTES = 131072
CHUNK_BYTES = 1024 * 1024
ATTACHMENT_NAME = re.compile(r"attachments/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.asset\Z")
DEFAULT_DATA_DIR = Path.home() / ".local/share/majoris/stickies"


class BackupError(Exception):
    """A backup, validation, or restore error that may be shown to users."""


def _digest_stream(source: BinaryIO, destination: BinaryIO | None = None) -> tuple[str, int]:
    """Hash bounded input while optionally copying it to a destination stream."""
    digest = hashlib.sha256()
    total = 0
    while chunk := source.read(CHUNK_BYTES):
        total += len(chunk)
        if total > MAX_ARCHIVE_BYTES:
            raise BackupError("An archive member exceeds the safety limit")
        digest.update(chunk)
        if destination is not None:
            destination.write(chunk)
    return digest.hexdigest(), total


def _quick_check(database_path: Path) -> tuple[int, list[str]]:
    """Validate a self-contained SQLite snapshot and identify referenced assets."""
    uri = f"file:{quote(str(database_path.absolute()))}?mode=ro"
    with closing(sqlite3.connect(uri, uri=True)) as connection:
        if connection.execute("PRAGMA quick_check(1)").fetchone() != ("ok",):
            raise BackupError("SQLite integrity validation failed")
        if connection.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise BackupError("A saved attachment has an invalid note reference")
        version = int(connection.execute("PRAGMA user_version").fetchone()[0])
        if version < 1 or version > 5:
            raise BackupError(f"Unsupported SQLite schema version: {version}")
        names = [] if version == 1 else [
            f"attachments/{row[0]}.asset" for row in
            connection.execute("SELECT id FROM attachments ORDER BY id")
        ]
    if len(names) > MAX_FILES or any(not ATTACHMENT_NAME.fullmatch(name) for name in names):
        raise BackupError("Attachment identifiers or count are invalid")
    if len(set(names)) != len(names):
        raise BackupError("Duplicate attachment identities in the database")
    return version, names


def _regular_file(path: Path, size_limit: int) -> None:
    """Refuse symlinks, devices, missing assets, and oversized files."""
    try:
        info = path.lstat()
    except FileNotFoundError as error:
        raise BackupError(f"Missing backup input: {path.name}") from error
    if not stat.S_ISREG(info.st_mode) or info.st_size > size_limit:
        raise BackupError(f"Not a supported regular file: {path.name}")


def create_backup(data_dir: Path, archive_path: Path) -> None:
    """Take an SQLite-consistent snapshot and bundle all referenced attachments."""
    data_dir = data_dir.resolve()
    archive_path = archive_path.absolute()
    _regular_file(data_dir / "notes.db", MAX_ARCHIVE_BYTES)
    if archive_path.exists():
        raise BackupError("The backup destination already exists")
    if not archive_path.parent.is_dir():
        raise BackupError("The backup destination directory does not exist")

    with tempfile.TemporaryDirectory(prefix="stickies-snapshot-") as scratch:
        database_copy = Path(scratch) / "notes.db"
        source_uri = f"file:{quote(str(data_dir / 'notes.db'))}?mode=ro"
        with closing(sqlite3.connect(source_uri, uri=True, timeout=5)) as source:
            with closing(sqlite3.connect(database_copy)) as target:
                source.backup(target, pages=256, sleep=0.05)
        version, asset_names = _quick_check(database_copy)
        inputs = {"notes.db": database_copy}
        total_bytes = database_copy.stat().st_size
        layout_path = data_dir / "window-positions.json"
        if layout_path.exists() or layout_path.is_symlink():
            _regular_file(layout_path, MAX_LAYOUT_BYTES)
            inputs["window-positions.json"] = layout_path
            total_bytes += layout_path.stat().st_size
        for name in asset_names:
            path = data_dir / name
            _regular_file(path, MAX_ATTACHMENT_BYTES)
            total_bytes += path.stat().st_size
            if total_bytes > MAX_ARCHIVE_BYTES:
                raise BackupError("Backup content exceeds the maximum size")
            inputs[name] = path

        descriptor, temporary_path = tempfile.mkstemp(
            prefix=".stickies-backup-", suffix=".zip", dir=archive_path.parent
        )
        try:
            os.fchmod(descriptor, 0o600)
            os.close(descriptor)
            manifest: dict[str, object] = {
                "format": "majoris-stickies-backup",
                "version": ARCHIVE_VERSION,
                "schema_version": version,
                "files": {},
            }
            with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_STORED) as archive:
                for name, path in inputs.items():
                    with path.open("rb") as source, archive.open(name, "w") as target:
                        digest, size = _digest_stream(source, target)
                    manifest["files"][name] = {"sha256": digest, "size": size}
                archive.writestr("manifest.json", json.dumps(manifest, sort_keys=True))
            with open(temporary_path, "rb") as source:
                os.fsync(source.fileno())
            if archive_path.exists():
                raise BackupError("The backup destination was created during export")
            os.replace(temporary_path, archive_path)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)


def _read_manifest(archive: zipfile.ZipFile) -> dict[str, dict[str, object]]:
    """Reject unexpected filenames and untrusted archive metadata."""
    members = archive.infolist()
    names = [entry.filename for entry in members]
    if len(names) != len(set(names)) or len(names) > MAX_FILES + 2:
        raise BackupError("Duplicate or excessive archive entries")
    if "manifest.json" not in names or "notes.db" not in names:
        raise BackupError("The backup is missing its manifest or database")
    if any(name not in ("manifest.json", "notes.db", "window-positions.json") and
           not ATTACHMENT_NAME.fullmatch(name) for name in names):
        raise BackupError("The archive contains an unexpected path")
    if any((entry.external_attr >> 16) & 0o170000 == 0o120000 for entry in members):
        raise BackupError("Symbolic links are not permitted in backup archives")
    manifest_info = archive.getinfo("manifest.json")
    if manifest_info.file_size > MAX_MANIFEST_BYTES:
        raise BackupError("The manifest is too large")
    try:
        manifest = json.loads(archive.read("manifest.json"))
        files = manifest["files"]
        if (manifest["format"] != "majoris-stickies-backup" or
                manifest["version"] != ARCHIVE_VERSION or not isinstance(files, dict)):
            raise ValueError("Unexpected format or version")
        if set(files) != set(names) - {"manifest.json"}:
            raise ValueError("Manifest file list does not match the archive")
        for name, details in files.items():
            if (not isinstance(details, dict) or
                    not re.fullmatch(r"[0-9a-f]{64}", details["sha256"]) or
                    type(details["size"]) is not int or details["size"] < 0 or
                    details["size"] > MAX_ARCHIVE_BYTES or
                    archive.getinfo(name).file_size != details["size"]):
                raise ValueError("Invalid file metadata")
        return files
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise BackupError(f"Invalid backup manifest: {error}") from error


def verify_backup(archive_path: Path) -> None:
    """Check hashes, SQLite integrity, foreign keys, and all required asset IDs."""
    try:
        with zipfile.ZipFile(archive_path, "r") as archive:
            files = _read_manifest(archive)
            if sum(int(info["size"]) for info in files.values()) > MAX_ARCHIVE_BYTES:
                raise BackupError("Backup content exceeds the maximum size")
            with tempfile.TemporaryDirectory(prefix="stickies-verify-") as scratch:
                database_copy = Path(scratch) / "notes.db"
                for name, details in files.items():
                    destination = database_copy.open("wb") if name == "notes.db" else None
                    try:
                        with archive.open(name) as source:
                            digest, size = _digest_stream(source, destination)
                    finally:
                        if destination is not None:
                            destination.close()
                    if digest != details["sha256"] or size != details["size"]:
                        raise BackupError(f"Backup content does not match its manifest: {name}")
                schema_version, asset_names = _quick_check(database_copy)
                if set(asset_names) != set(files) - {"notes.db", "window-positions.json"}:
                    raise BackupError("Referenced attachments do not match the archive")
                with archive.open("manifest.json") as content:
                    saved_version = json.load(content)["schema_version"]
                if saved_version != schema_version:
                    raise BackupError("Database schema version does not match the manifest")
    except (OSError, sqlite3.DatabaseError, zipfile.BadZipFile, RuntimeError) as error:
        raise BackupError(f"Backup verification failed: {error}") from error


def restore_backup(archive_path: Path, destination_dir: Path) -> None:
    """Restore to a new directory atomically; never overwrite live user data."""
    destination_dir = destination_dir.absolute()
    if destination_dir.exists():
        raise BackupError("Restore destination exists; choose an unused directory")
    if not destination_dir.parent.is_dir():
        raise BackupError("Restore destination parent directory does not exist")
    verify_backup(archive_path)
    scratch = Path(tempfile.mkdtemp(prefix=".stickies-restore-", dir=destination_dir.parent))
    try:
        os.chmod(scratch, 0o700)
        with zipfile.ZipFile(archive_path, "r") as archive:
            files = _read_manifest(archive)
            for name in files:
                target = scratch / name
                target.parent.mkdir(mode=0o700, exist_ok=True)
                with archive.open(name) as source, target.open("xb") as destination:
                    digest, size = _digest_stream(source, destination)
                if digest != files[name]["sha256"] or size != files[name]["size"]:
                    raise BackupError(f"Archive changed during restoration: {name}")
                target.chmod(0o600)
        if destination_dir.exists():
            raise BackupError("Restore destination was created during recovery")
        scratch.rename(destination_dir)
    finally:
        if scratch.exists():
            shutil.rmtree(scratch)


def main(argv: list[str] | None = None) -> int:
    """Run an explicit backup, integrity verification, or offline restore."""
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    backup = subcommands.add_parser("backup", help="Create an archive without stopping Stickies")
    backup.add_argument("output", type=Path)
    backup.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    check = subcommands.add_parser("verify", help="Validate a complete backup archive")
    check.add_argument("archive", type=Path)
    restore = subcommands.add_parser("restore", help="Restore into a new directory (Stickies closed)")
    restore.add_argument("archive", type=Path)
    restore.add_argument("destination", type=Path)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "backup":
            create_backup(arguments.data_dir, arguments.output)
        elif arguments.command == "verify":
            verify_backup(arguments.archive)
        else:
            restore_backup(arguments.archive, arguments.destination)
    except BackupError as error:
        print(f"Stickies backup: {error}", file=sys.stderr)
        return 1
    print(f"Stickies {arguments.command}: success")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
