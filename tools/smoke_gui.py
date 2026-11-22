#!/usr/bin/env python3
"""Run a bounded native GTK startup/activation smoke test under Xvfb.

Invoke inside a private D-Bus session and an X server after a native build:
    xvfb-run -a dbus-run-session -- python3 tools/smoke_gui.py build/src/majoris-stickies

This exercises application activation and command routing, not compositor-only
GNOME Shell behavior, screen readers, portals, or native Wayland correctness.
"""

from __future__ import annotations

from contextlib import closing

import os
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

STARTUP_TIMEOUT_SECONDS = 12
COMMAND_TIMEOUT_SECONDS = 8


def main(argv: list[str] | None = None) -> int:
    """Start one application, call its single-instance routes, and exit cleanly."""
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) != 1 or not Path(arguments[0]).is_file():
        print("Usage: smoke_gui.py PATH_TO_MAJORIS_STICKIES", file=sys.stderr)
        return 2
    binary = str(Path(arguments[0]).resolve())
    with tempfile.TemporaryDirectory(prefix="stickies-gui-smoke-") as root:
        environment = dict(os.environ)
        environment["XDG_DATA_HOME"] = str(Path(root) / "data")
        environment["XDG_CONFIG_HOME"] = str(Path(root) / "config")
        environment["XDG_CACHE_HOME"] = str(Path(root) / "cache")
        environment["XDG_STATE_HOME"] = str(Path(root) / "state")
        environment["GDK_BACKEND"] = "x11"
        environment["GSK_RENDERER"] = "cairo"
        process = subprocess.Popen(
            [binary], env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True,
        )
        try:
            notes_path = Path(root) / "data/majoris/stickies/notes.db"
            deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"Stickies exited before startup: {process.returncode}")
                if notes_path.is_file():
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("Timed out waiting for the notes database")
            with closing(sqlite3.connect(f"file:{notes_path}?mode=ro", uri=True)) as database:
                initial_count = database.execute("SELECT count(*) FROM notes").fetchone()[0]
            for option in ("--new-note", "--show-notes"):
                command = subprocess.run(
                    [binary, option], env=environment, text=True,
                    capture_output=True, timeout=COMMAND_TIMEOUT_SECONDS,
                    check=False,
                )
                if command.returncode != 0:
                    raise RuntimeError(
                        f"{option} failed with {command.returncode}: {command.stderr}"
                    )
            with closing(sqlite3.connect(f"file:{notes_path}?mode=ro", uri=True)) as database:
                resulting_count = database.execute("SELECT count(*) FROM notes").fetchone()[0]
            if resulting_count != initial_count + 1:
                raise RuntimeError(
                    "New Note did not persist exactly one note, or Show Notes created an extra"
                )
            invalid = subprocess.run(
                [binary, "--unknown-option"], env=environment, text=True,
                capture_output=True, timeout=COMMAND_TIMEOUT_SECONDS, check=False,
            )
            if invalid.returncode != 2:
                raise RuntimeError("An invalid desktop action was unexpectedly accepted")
            if process.poll() is not None:
                raise RuntimeError("The primary Stickies process crashed during activation")
        except (OSError, sqlite3.Error, RuntimeError, subprocess.TimeoutExpired) as error:
            print(f"GTK smoke test failed: {error}", file=sys.stderr)
            return 1
        finally:
            process.terminate()
            try:
                _, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                _, stderr = process.communicate()
            if stderr and process.returncode not in (0, -15):
                print(stderr[-4000:], file=sys.stderr)
    print("GTK startup and single-instance activation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
