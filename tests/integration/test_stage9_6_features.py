"""Exercise custom paper colors, recurring reminders, and v7 legacy compatibility."""

from __future__ import annotations

from contextlib import closing
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
DAY_US = 86_400_000_000
WEEK_US = 7 * DAY_US


def _tool(name: str):
    """Import the shipping tool in isolation without side effects."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    assert spec and spec.loader
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


exchange = _tool("stickies_exchange")
reminders = _tool("stickies_reminders")
backup = _tool("stickies_backup")


class Stage96Features(unittest.TestCase):
    """Verify external formats and behavior independently of GTK rendering."""

    def setUp(self) -> None:
        """Create independent, realistic schema-v7 and v6 stores."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        session = patch.object(exchange, "_application_is_running", return_value=False)
        session.start()
        self.addCleanup(session.stop)
        self.root = Path(scratch.name)
        self.first = self.root / "first"
        self.other = self.root / "other"
        self.legacy = self.root / "legacy"
        for path, schema in ((self.first, 7), (self.other, 7), (self.legacy, 6)):
            path.mkdir(mode=0o700)
            with closing(sqlite3.connect(path / "notes.db")) as db:
                db.executescript(f"""
                    PRAGMA user_version={schema};
                    PRAGMA foreign_keys=ON;
                    CREATE TABLE notes (
                        id TEXT PRIMARY KEY, title TEXT NOT NULL,
                        content TEXT NOT NULL, color TEXT NOT NULL,
                        created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL,
                        formatting TEXT NOT NULL DEFAULT '', collapsed INTEGER NOT NULL DEFAULT 0,
                        floating INTEGER NOT NULL DEFAULT 0, translucent INTEGER NOT NULL DEFAULT 0,
                        window_width INTEGER NOT NULL DEFAULT 370,
                        window_height INTEGER NOT NULL DEFAULT 330,
                        visible INTEGER NOT NULL DEFAULT 0, source_url TEXT NOT NULL DEFAULT '',
                        remind_at_us INTEGER NOT NULL DEFAULT 0,
                        reminder_notified_at_us INTEGER NOT NULL DEFAULT 0,
                        status INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0,
                        auto_title INTEGER NOT NULL DEFAULT 0
                        {', reminder_repeat_us INTEGER NOT NULL DEFAULT 0' if schema == 7 else ''}
                    );
                    CREATE TABLE attachments (
                        id TEXT PRIMARY KEY NOT NULL,
                        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL, mime_type TEXT NOT NULL
                    );
                """)
        self.note_id = str(uuid.uuid4())
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us, "
                "remind_at_us,auto_title,reminder_repeat_us) "
                "VALUES(?,?,?,?,?,?,?,?,?)",
                (self.note_id, "Repeat Task", "Paper", "#efdecb", 10, 11, 100, 1, DAY_US),
            )
            db.commit()

    def _row(self, path: Path) -> tuple[str, int, int, int]:
        """Read the color, deadline, delivery marker, and interval."""
        with closing(sqlite3.connect(path / "notes.db")) as db:
            return db.execute(
                "SELECT color,remind_at_us,reminder_notified_at_us,reminder_repeat_us "
                "FROM notes WHERE id=?", (self.note_id,),
            ).fetchone()

    def test_custom_colors_round_trip_and_backup(self) -> None:
        """Preserve a pastel color across a v7 bundle and verified backup."""
        bundle = self.root / "note.stickies"
        exchange.share_note(self.first, self.note_id, bundle)
        with zipfile.ZipFile(bundle) as archive:
            manifest = json.loads(archive.read("manifest.json"))
        self.assertEqual(manifest["note"]["color"], "#efdecb")
        self.assertEqual(manifest["note"]["reminder_repeat_us"], DAY_US)
        self.assertEqual(exchange.import_note(self.other, bundle, True), "Note imported")
        self.assertEqual(self._row(self.first), self._row(self.other))
        destination = self.root / "backup.zip"
        backup.create_backup(self.first, destination)
        backup.verify_backup(destination)

    def test_reject_dark_malformed_and_css_injection(self) -> None:
        """Require exactly six lowercase hex digits and bright paper."""
        for color in ("#ffffff", "#efdecb", "#c0c0c0", "yellow"):
            with self.subTest(color=color):
                with closing(sqlite3.connect(self.first / "notes.db")) as db:
                    db.execute("UPDATE notes SET color=?", (color,))
                    db.commit()
                exchange.share_note(self.first, self.note_id, self.root / f"valid{len(color)}-{color.lstrip('#')}.stickies")
        for color in ("#000000", "#123456", "#FFFFFF", "#fed", "#eeffee;}", "pink\n"):
            with self.subTest(color=color):
                with closing(sqlite3.connect(self.first / "notes.db")) as db:
                    db.execute("UPDATE notes SET color=?", (color,))
                    db.commit()
                with self.assertRaises(exchange.ExchangeError):
                    exchange.share_note(self.first, self.note_id, self.root / "bad.stickies")

    def test_recurrence_skips_missed_intervals(self) -> None:
        """Notify once and retain the next future 24-hour occurrence."""
        delivered: list[str] = []
        now = 2 * DAY_US + 1000
        self.assertEqual(reminders.dispatch_due(
            self.first, now_us=now, is_running=lambda: False, notify=delivered.append,
        ), 1)
        self.assertEqual(delivered, ["Repeat Task"])
        self.assertEqual(self._row(self.first)[1:], (100 + 3 * DAY_US, 0, DAY_US))
        self.assertEqual(reminders.dispatch_due(
            self.first, now_us=now, is_running=lambda: False, notify=delivered.append,
        ), 0)
        self.assertEqual(len(delivered), 1)

    def test_weekly_recurrence_and_notification_failure(self) -> None:
        """Leave a failed submission pending, then advance one week."""
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute("UPDATE notes SET reminder_repeat_us=?", (WEEK_US,))
            db.commit()
        def failed(_title: str) -> None:
            """Represent a failed notification server."""
            raise reminders.ReminderError("Notifications unavailable")
        with self.assertRaises(reminders.ReminderError):
            reminders.dispatch_due(
                self.first, now_us=200, is_running=lambda: False, notify=failed,
            )
        self.assertEqual(self._row(self.first)[1:], (100, 0, WEEK_US))
        self.assertEqual(reminders.dispatch_due(
            self.first, now_us=200, is_running=lambda: False, notify=lambda _: None,
        ), 1)
        self.assertEqual(self._row(self.first)[1:], (100 + WEEK_US, 0, WEEK_US))

    def test_background_worker_respects_gui_store_lock(self) -> None:
        """Prevent the background reminder worker from racing the application."""
        with exchange.exclusive_store_lock(self.first):
            with self.assertRaisesRegex(reminders.ReminderError, "open or another worker"):
                reminders.dispatch_due(
                    self.first, now_us=200, is_running=lambda: False,
                    notify=lambda _: None,
                )
        self.assertEqual(self._row(self.first)[1:], (100, 0, DAY_US))

    def test_older_schema_rejects_recurring_note_without_loss(self) -> None:
        """Avoid silently discarding recurrence when importing into schema v6."""
        bundle = self.root / "recurring.stickies"
        exchange.share_note(self.first, self.note_id, bundle)
        with self.assertRaisesRegex(exchange.ExchangeError, "Upgrade Stickies"):
            exchange.import_note(self.legacy, bundle, True)
        with closing(sqlite3.connect(self.legacy / "notes.db")) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM notes").fetchone(), (0,))

    def test_invalid_recurrence_fails_closed(self) -> None:
        """Reject unsupported or unbounded recurrence intervals on export."""
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute("UPDATE notes SET reminder_repeat_us=?", (1000,))
            db.commit()
        with self.assertRaisesRegex(exchange.ExchangeError, "recurrence"):
            exchange.share_note(self.first, self.note_id, self.root / "bad.stickies")


if __name__ == "__main__":
    unittest.main()
