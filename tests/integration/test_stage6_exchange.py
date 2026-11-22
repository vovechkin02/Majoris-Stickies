"""Exercise the Stage 6 lifecycle fields in portable note exchange."""

from __future__ import annotations

import importlib.util
import json
import sqlite3
import tempfile
import unittest
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_exchange", ROOT / "tools/stickies_exchange.py")
assert SPEC and SPEC.loader
exchange = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exchange)


class Stage6ExchangeTests(unittest.TestCase):
    """Verify v5 lifecycle sharing and strict handling of untrusted states."""

    def setUp(self) -> None:
        """Initialize one isolated v5 note store with no external accounts."""
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.note_id = str(uuid.uuid4())
        self.store = self.root / "store"
        self.store.mkdir()
        with sqlite3.connect(self.store / "notes.db") as db:
            db.executescript("""
                PRAGMA user_version=5;
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL,
                    content TEXT NOT NULL, color TEXT NOT NULL,
                    created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL,
                    formatting TEXT NOT NULL DEFAULT '', collapsed INTEGER NOT NULL DEFAULT 0,
                    floating INTEGER NOT NULL DEFAULT 0,
                    translucent INTEGER NOT NULL DEFAULT 0,
                    window_width INTEGER NOT NULL DEFAULT 370,
                    window_height INTEGER NOT NULL DEFAULT 330,
                    visible INTEGER NOT NULL DEFAULT 0,
                    source_url TEXT NOT NULL DEFAULT '',
                    remind_at_us INTEGER NOT NULL DEFAULT 0,
                    reminder_notified_at_us INTEGER NOT NULL DEFAULT 0,
                    status INTEGER NOT NULL DEFAULT 0,
                    pinned INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE attachments (
                    id TEXT PRIMARY KEY NOT NULL,
                    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                    display_name TEXT NOT NULL,
                    mime_type TEXT NOT NULL
                );
            """)
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us,status,pinned) "
                "VALUES(?,?,?,?,?,?,?,?)",
                (self.note_id, "Archive", "Saved content", "green", 10, 11, 1, 1),
            )

    def test_archive_roundtrip(self) -> None:
        """Preserve archived/pinned state in a v5 portable share."""
        output = self.root / "shared.stickies"
        exchange.share_note(self.store, self.note_id, output)
        note, assets, revision = exchange._read_bundle(output)
        self.assertEqual((note["status"], note["pinned"]), (1, 1))
        self.assertEqual(assets, {})
        self.assertEqual(len(revision), 64)
        with zipfile.ZipFile(output) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(len(manifest["note"]), 18)

    def test_reject_unknown_state(self) -> None:
        """Reject serialized lifecycle states outside the domain contract."""
        with sqlite3.connect(self.store / "notes.db") as db:
            db.execute("UPDATE notes SET status=99")
        with self.assertRaises(exchange.ExchangeError):
            exchange.share_note(self.store, self.note_id, self.root / "invalid.stickies")

    def test_backup_v5_schema(self) -> None:
        """Backup tool must accept version 5 without modifying note contents."""
        spec = importlib.util.spec_from_file_location("stickies_backup", ROOT / "tools/stickies_backup.py")
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        archive = self.root / "backup.zip"
        module.create_backup(self.store, archive)
        module.verify_backup(archive)


if __name__ == "__main__":
    unittest.main()
