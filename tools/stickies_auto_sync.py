#!/usr/bin/env python3
"""Opt-in scheduled synchronization of an existing, local Stickies share folder.

This helper never contacts a cloud account, starts the GUI, or propagates
permanent deletions. It invokes the existing conflict-preserving exchange CLI
only after checking the user session and a private configuration file.
"""

from __future__ import annotations

import argparse
import configparser
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

MAX_CONFIG_BYTES = 4096
SYNC_TIMEOUT_SECONDS = 120


class AutoSyncError(RuntimeError):
    """Reject an unsafe automatic sync or unavailable user session."""


def configuration_path() -> Path:
    """Resolve the user-scoped config using only absolute XDG directories."""
    value = os.environ.get("XDG_CONFIG_HOME", "")
    base = Path(value) if value else Path.home() / ".config"
    if not base.is_absolute():
        base = Path.home() / ".config"
    return base / "majoris" / "stickies" / "sync.ini"


def data_directory() -> Path:
    """Match GLib's XDG_DATA_HOME directory for the application's SQLite store."""
    value = os.environ.get("XDG_DATA_HOME", "")
    base = Path(value) if value else Path.home() / ".local" / "share"
    if not base.is_absolute():
        base = Path.home() / ".local" / "share"
    return base / "majoris" / "stickies"


def _validate_folder(folder: Path) -> None:
    """Refuse nonexistent, non-absolute, and symlinked share folders."""
    if not folder.is_absolute() or folder.is_symlink() or not folder.is_dir():
        raise AutoSyncError("Choose an existing, real, absolute share directory")


def configure(folder: Path, *, replace: bool = False) -> Path:
    """Create a private, bounded config without silently replacing existing settings."""
    _validate_folder(folder)
    path = configuration_path()
    if path.exists() or path.is_symlink():
        if not replace or path.is_symlink():
            raise AutoSyncError("Configuration exists; use --replace to change it")
        _check_private_config(path)
    parent = path.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if parent.is_symlink():
        raise AutoSyncError("Configuration directory must not be a symbolic link")
    text = "[Sync]\nfolder = " + str(folder) + "\n"
    if len(text.encode("utf-8")) > MAX_CONFIG_BYTES or any(
        ord(character) < 32 for character in str(folder)
    ):
        raise AutoSyncError("Share path is too long or contains a newline")
    descriptor, temporary = tempfile.mkstemp(prefix=".sync-", dir=parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        if (path.exists() or path.is_symlink()) and not replace:
            raise AutoSyncError("Configuration was created concurrently")
        if replace:
            os.replace(temporary, path)
        else:
            try:
                os.link(temporary, path)
            except FileExistsError as error:
                raise AutoSyncError("Configuration was created concurrently") from error
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return path


def _check_private_config(path: Path) -> None:
    """Require a regular owner-only config, not a link or device."""
    try:
        info = path.lstat()
    except OSError as error:
        raise AutoSyncError("Automatic sync has not been configured") from error
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or
            info.st_mode & 0o077 or info.st_size > MAX_CONFIG_BYTES):
        raise AutoSyncError("Automatic sync requires an owner-only regular config file")


def configured_folder() -> Path:
    """Read only one validated local folder from the private settings."""
    path = configuration_path()
    _check_private_config(path)
    try:
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        with path.open("r", encoding="utf-8") as stream:
            parser.read_file(stream)
        folder = Path(parser.get("Sync", "folder"))
    except (OSError, UnicodeError, configparser.Error) as error:
        raise AutoSyncError("Invalid automatic-sync configuration") from error
    _validate_folder(folder)
    return folder


def application_is_running() -> bool:
    """Fail closed unless the session bus confirms Stickies is not running."""
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise AutoSyncError("A verified user session bus is required")
    try:
        result = subprocess.run(
            ["dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.DBus",
             "/org/freedesktop/DBus", "org.freedesktop.DBus.NameHasOwner",
             "string:com.majoris.stickies"],
            check=True, capture_output=True, text=True, timeout=3,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise AutoSyncError("Could not verify Stickies application state") from error
    if "boolean true" in result.stdout:
        return True
    if "boolean false" in result.stdout:
        return False
    raise AutoSyncError("Unexpected user session response")


def synchronize_once(*, dry_run: bool = False) -> str:
    """Run conflict-aware synchronization only with explicit configuration."""
    folder = configured_folder()
    if application_is_running():
        return "Skipped: Stickies is running"
    store = data_directory()
    if store.is_symlink() or not store.is_dir():
        raise AutoSyncError("The Stickies data directory is unavailable")
    if dry_run:
        return "Ready: folder validated and Stickies is closed"
    command = [
        "majoris-stickies-exchange", "--data-dir", str(store),
        "sync", str(folder), "--app-closed",
    ]
    try:
        result = subprocess.run(
            command, check=False, capture_output=True, text=True,
            timeout=SYNC_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AutoSyncError("The local exchange operation could not finish") from error
    if result.returncode != 0:
        raise AutoSyncError("Local exchange failed: " + result.stderr.strip()[:240])
    return result.stdout.strip()


def main(argv: list[str] | None = None) -> int:
    """Configure or execute an explicit opt-in local sync operation."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("configure", help="Set an existing local sync folder")
    setup.add_argument("folder", type=Path)
    setup.add_argument("--replace", action="store_true")
    once = commands.add_parser("once", help="Sync now if the desktop app is closed")
    once.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "configure":
            path = configure(args.folder, replace=args.replace)
            print(f"Automatic sync configured locally: {path}")
        else:
            print(synchronize_once(dry_run=args.dry_run))
    except AutoSyncError as error:
        print(f"Automatic sync: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
