#!/usr/bin/env python3
"""Dispatch due local Stickies reminders while the desktop app is closed.

This opt-in, offline worker never uploads note content or starts the GTK app.
The user timer is disabled by default. A successful notification submission is
recorded in the existing schema, while failed submissions remain retryable.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import time
from typing import Callable

DATA_DIR = Path.home() / ".local/share/majoris/stickies"
MAX_DUE_PER_RUN = 30
MAX_DATABASE_BYTES = 1024 * 1024 * 1024


class ReminderError(RuntimeError):
    """Indicate that a background notification cannot be delivered safely."""


def application_is_running() -> bool:
    """Fail closed if the user-session bus cannot be queried reliably."""
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise ReminderError("A user session D-Bus connection is required")
    try:
        result = subprocess.run(
            ["dbus-send", "--session", "--print-reply",
             "--dest=org.freedesktop.DBus", "/org/freedesktop/DBus",
             "org.freedesktop.DBus.NameHasOwner", "string:com.majoris.stickies"],
            check=True, capture_output=True, text=True, timeout=3,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ReminderError("Cannot verify whether Stickies is running") from error
    if "boolean true" in result.stdout:
        return True
    if "boolean false" in result.stdout:
        return False
    raise ReminderError("Unexpected response from the user session bus")


def send_notification(title: str) -> None:
    """Submit a bounded, local desktop notification without shell expansion."""
    try:
        subprocess.run(
            ["notify-send", "--app-name=Stickies", "--icon=com.majoris.stickies",
             "Stickies reminder", title[:160]],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            timeout=8,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ReminderError("Desktop notification service is unavailable") from error


def dispatch_due(
    data_dir: Path,
    *,
    now_us: int | None = None,
    is_running: Callable[[], bool] = application_is_running,
    notify: Callable[[str], None] = send_notification,
    dry_run: bool = False,
) -> int:
    """Submit due notes and persist acknowledgements only after successful dispatch.

    Only active, unnotified reminders in SQLite schema 4 or 5 are considered.
    The worker never creates or migrates a database. It yields to an existing
    application session, leaving that app as the sole reminder dispatcher.
    """
    if is_running():
        return 0
    path = data_dir / "notes.db"
    if data_dir.is_symlink() or not data_dir.is_dir() or path.is_symlink():
        raise ReminderError("The Stickies data path must be a real directory")
    try:
        info = path.stat()
    except OSError as error:
        raise ReminderError("The local notes database is unavailable") from error
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_DATABASE_BYTES:
        raise ReminderError("Unsafe or oversized notes database")
    when = (time.time_ns() // 1000) if now_us is None else now_us
    if when <= 0:
        raise ReminderError("Invalid current time")
    uri = path.resolve().as_uri() + "?mode=rw"
    count = 0
    with closing(sqlite3.connect(uri, uri=True, timeout=1)) as connection:
        connection.execute("PRAGMA busy_timeout=1000")
        schema = connection.execute("PRAGMA user_version").fetchone()[0]
        if schema not in (4, 5):
            raise ReminderError("Unsupported notes schema; open Stickies to upgrade")
        status_filter = "AND status=0" if schema >= 5 else ""
        query = (
            "SELECT id,title,remind_at_us FROM notes WHERE remind_at_us>0 "
            "AND reminder_notified_at_us=0 AND remind_at_us<=? "
            f"{status_filter} ORDER BY remind_at_us ASC LIMIT ?"
        )
        due = connection.execute(query, (when, MAX_DUE_PER_RUN)).fetchall()
        for identity, title, deadline in due:
            if is_running():
                break
            if dry_run:
                count += 1
                continue
            notify(title)
            # The update compares the original deadline so a modified reminder
            # can never be acknowledged on behalf of a new reminder.
            cursor = connection.execute(
                "UPDATE notes SET reminder_notified_at_us=? WHERE id=? "
                "AND remind_at_us=? AND reminder_notified_at_us=0",
                (when, identity, deadline),
            )
            connection.commit()
            count += int(cursor.rowcount == 1)
    return count


def main(argv: list[str] | None = None) -> int:
    """Dispatch one bounded pass suitable for an opt-in systemd user timer."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        total = dispatch_due(args.data_dir, dry_run=args.dry_run)
    except (ReminderError, sqlite3.Error) as error:
        print(f"Background reminders: {error}", file=sys.stderr)
        return 1
    print(f"{'Due' if args.dry_run else 'Submitted'} reminders: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
