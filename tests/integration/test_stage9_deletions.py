"""Check opt-in sync deletion propagation without silent remote data loss."""

from __future__ import annotations

from contextlib import closing
import importlib.util
import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_exchange", ROOT / "tools/stickies_exchange.py")
assert SPEC and SPEC.loader
exchange = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exchange)


class DeletionSyncTests(unittest.TestCase):
    """Require explicit user permission and prior sync evidence for deletions."""

    def setUp(self) -> None:
        """Create two independent stores and a previously shared note."""
        patcher = patch.object(exchange, "_application_is_running", return_value=False)
        patcher.start()
        self.addCleanup(patcher.stop)
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        self.root = Path(root.name)
        self.first = self.root / "first"
        self.second = self.root / "second"
        self.shared = self.root / "shared"
        self.note_id = str(uuid.uuid4())
        for folder in (self.first, self.second, self.shared):
            folder.mkdir()
        for folder in (self.first, self.second):
            with closing(sqlite3.connect(folder / "notes.db")) as db:
                db.executescript("""
                    PRAGMA user_version=5;
                    CREATE TABLE notes (
                        id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL,
                        content TEXT NOT NULL, color TEXT NOT NULL,
                        created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL,
                        formatting TEXT NOT NULL DEFAULT '', collapsed INTEGER NOT NULL DEFAULT 0,
                        floating INTEGER NOT NULL DEFAULT 0, translucent INTEGER NOT NULL DEFAULT 0,
                        window_width INTEGER NOT NULL DEFAULT 370,
                        window_height INTEGER NOT NULL DEFAULT 330,
                        visible INTEGER NOT NULL DEFAULT 0, source_url TEXT NOT NULL DEFAULT '',
                        remind_at_us INTEGER NOT NULL DEFAULT 0,
                        reminder_notified_at_us INTEGER NOT NULL DEFAULT 0,
                        status INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0
                    );
                    CREATE TABLE attachments (
                        id TEXT PRIMARY KEY NOT NULL,
                        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL, mime_type TEXT NOT NULL
                    );
                """)
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) "
                "VALUES(?,?,?,?,?,?)", (self.note_id, "Task", "body", "yellow", 1, 2),
            )
            db.commit()
        self.assertEqual(exchange.sync_folder(self.first, self.shared, True)["published"], 1)
        self.assertEqual(exchange.sync_folder(self.second, self.shared, True)["received"], 1)

    def _delete(self, folder: Path) -> None:
        """Permanently remove one local note, matching the app's delete contract."""
        with closing(sqlite3.connect(folder / "notes.db")) as db:
            db.execute("DELETE FROM notes WHERE id=?", (self.note_id,))
            db.commit()

    def _count(self, folder: Path) -> int:
        """Read the remaining notes in the isolated store."""
        with closing(sqlite3.connect(folder / "notes.db")) as db:
            return db.execute("SELECT COUNT(*) FROM notes").fetchone()[0]

    def test_no_deletion_without_explicit_option(self) -> None:
        """Leave old default sync behavior unchanged unless deletion is authorized."""
        self._delete(self.first)
        self.assertEqual(exchange.sync_folder(self.first, self.shared, True)["received"], 1)
        self.assertEqual(self._count(self.first), 1)
        self.assertFalse((self.shared / f"{self.note_id}.deleted").exists())

    def test_propagate_confirmed_deletion(self) -> None:
        """Publish and apply a bounded tombstone only after both explicit confirmations."""
        self._delete(self.first)
        self.assertEqual(exchange.sync_folder(
            self.first, self.shared, True, propagate_deletions=True
        )["deleted"], 1)
        self.assertFalse((self.shared / f"{self.note_id}.stickies").exists())
        self.assertTrue((self.shared / f"{self.note_id}.deleted").exists())
        with self.assertRaises(exchange.ExchangeError):
            exchange.sync_folder(self.second, self.shared, True)
        self.assertEqual(self._count(self.second), 1)
        self.assertEqual(exchange.sync_folder(
            self.second, self.shared, True, propagate_deletions=True
        )["deleted"], 1)
        self.assertEqual(self._count(self.second), 0)
        self.assertEqual(exchange.sync_folder(
            self.second, self.shared, True, propagate_deletions=True
        )["unchanged"], 0)
        self.assertEqual(self._count(self.second), 0)

    def test_divergent_remote_edit_is_not_destroyed(self) -> None:
        """Preserve an edited peer note as a conflict copy before applying deletion."""
        with closing(sqlite3.connect(self.second / "notes.db")) as db:
            db.execute("UPDATE notes SET content='Retain this edit',updated_at_us=30")
            db.commit()
        self._delete(self.first)
        exchange.sync_folder(self.first, self.shared, True, propagate_deletions=True)
        result = exchange.sync_folder(self.second, self.shared, True, propagate_deletions=True)
        self.assertEqual(result["conflicts"], 1)
        with closing(sqlite3.connect(self.second / "notes.db")) as db:
            saved = db.execute("SELECT id,content FROM notes").fetchall()
        self.assertEqual(len(saved), 1)
        self.assertNotEqual(saved[0][0], self.note_id)
        self.assertEqual(saved[0][1], "Retain this edit")

    def test_deletion_conflicts_with_newer_shared_edit(self) -> None:
        """Reject a local deletion when the peer has independently edited the note."""
        with closing(sqlite3.connect(self.second / "notes.db")) as db:
            db.execute("UPDATE notes SET content='Updated remotely',updated_at_us=30")
            db.commit()
        exchange.sync_folder(self.second, self.shared, True)
        self._delete(self.first)
        with self.assertRaises(exchange.ExchangeError):
            exchange.sync_folder(self.first, self.shared, True, propagate_deletions=True)
        self.assertFalse((self.shared / f"{self.note_id}.deleted").exists())


if __name__ == "__main__":
    unittest.main()
