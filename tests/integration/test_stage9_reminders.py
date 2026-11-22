"""Check the optional local reminder worker without requiring a GUI session."""

from __future__ import annotations

from contextlib import closing
import importlib.util
import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_reminders", ROOT / "tools/stickies_reminders.py")
assert SPEC and SPEC.loader
reminders = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reminders)


class ReminderWorkerTests(unittest.TestCase):
    """Preserve due reminders until submission and never conflict with a running app."""

    def setUp(self) -> None:
        """Initialize a version-five database with due and future reminders."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.data = Path(directory.name)
        self.note_id = str(uuid.uuid4())
        self.future_id = str(uuid.uuid4())
        self.archive_id = str(uuid.uuid4())
        with closing(sqlite3.connect(self.data / "notes.db")) as db:
            db.executescript("""
                PRAGMA user_version=5;
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL,
                    remind_at_us INTEGER NOT NULL,
                    reminder_notified_at_us INTEGER NOT NULL DEFAULT 0,
                    status INTEGER NOT NULL DEFAULT 0
                );
            """)
            for identity, title, deadline, status in (
                (self.note_id, "Task is due", 100, 0),
                (self.future_id, "Later", 300, 0),
                (self.archive_id, "Archived", 50, 1),
            ):
                db.execute("INSERT INTO notes VALUES (?,?,?,?,?)", (
                    identity, title, deadline, 0, status,
                ))
            db.commit()

    def _marker(self) -> int:
        """Read the delivery marker without keeping a database connection open."""
        with closing(sqlite3.connect(self.data / "notes.db")) as db:
            return db.execute(
                "SELECT reminder_notified_at_us FROM notes WHERE id=?", (self.note_id,)
            ).fetchone()[0]

    def test_delivers_due_only_and_never_repeats(self) -> None:
        """Dispatch once and leave future, archived and already delivered notes alone."""
        submitted: list[str] = []
        run = lambda: reminders.dispatch_due(
            self.data, now_us=200, is_running=lambda: False, notify=submitted.append,
        )
        self.assertEqual(run(), 1)
        self.assertEqual(submitted, ["Task is due"])
        self.assertEqual(self._marker(), 200)
        self.assertEqual(run(), 0)
        self.assertEqual(submitted, ["Task is due"])

    def test_submission_failure_keeps_pending_reminder(self) -> None:
        """Allow the timer to retry if notification dispatch fails."""
        def unavailable(_title: str) -> None:
            """Simulate a missing desktop notification server."""
            raise reminders.ReminderError("Unavailable")
        with self.assertRaises(reminders.ReminderError):
            reminders.dispatch_due(
                self.data, now_us=200, is_running=lambda: False, notify=unavailable,
            )
        self.assertEqual(self._marker(), 0)

    def test_active_app_and_dry_run_never_mutate(self) -> None:
        """Skip while the app runs and allow a safe preview without notifying."""
        called: list[str] = []
        self.assertEqual(reminders.dispatch_due(
            self.data, now_us=200, is_running=lambda: True, notify=called.append,
        ), 0)
        self.assertEqual(reminders.dispatch_due(
            self.data, now_us=200, is_running=lambda: False,
            notify=called.append, dry_run=True,
        ), 1)
        self.assertEqual(called, [])
        self.assertEqual(self._marker(), 0)

    def test_unsupported_schema_is_rejected(self) -> None:
        """Never silently migrate a database from a background user service."""
        with closing(sqlite3.connect(self.data / "notes.db")) as db:
            db.execute("PRAGMA user_version=6")
            db.commit()
        with self.assertRaises(reminders.ReminderError):
            reminders.dispatch_due(
                self.data, now_us=200, is_running=lambda: False,
            )


if __name__ == "__main__":
    unittest.main()
