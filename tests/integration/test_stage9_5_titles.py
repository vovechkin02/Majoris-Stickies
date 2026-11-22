"""Verify title-mode interchange, v5 compatibility and backups using SQLite."""

from __future__ import annotations

import importlib.util
import json
import sqlite3
import tempfile
import unittest
import uuid
import zipfile
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def _load(name: str):
    """Load the actual installed-tool source without subprocess side effects."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


exchange = _load("stickies_exchange")
backup = _load("stickies_backup")


class TitleModeExchangeTests(unittest.TestCase):
    """Prove new semantic fields survive exchange without breaking old bundles."""

    def setUp(self) -> None:
        """Create isolated v5 and v6 repositories with safe temp paths."""
        session_check = patch.object(exchange, "_application_is_running", return_value=False)
        session_check.start()
        self.addCleanup(session_check.stop)
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.old = self.root / "old"
        self.new = self.root / "new"
        self.other = self.root / "other"
        for location, version in ((self.old, 5), (self.new, 6), (self.other, 6)):
            location.mkdir()
            with closing(sqlite3.connect(location / "notes.db")) as database:
                database.executescript(f"""
                    PRAGMA user_version={version};
                    PRAGMA foreign_keys=ON;
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
                        {', auto_title INTEGER NOT NULL DEFAULT 0' if version == 6 else ''}
                    );
                    CREATE TABLE attachments (
                        id TEXT PRIMARY KEY NOT NULL,
                        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL, mime_type TEXT NOT NULL
                    );
                """)
        self.auto_id = str(uuid.uuid4())
        self.manual_id = str(uuid.uuid4())
        self.old_id = str(uuid.uuid4())
        with closing(sqlite3.connect(self.new / "notes.db")) as db:
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us,auto_title) "
                "VALUES(?,?,?,?,?,?,?)",
                (self.auto_id, "First line", "First line\nBody", "yellow", 10, 11, 1),
            )
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us,auto_title) "
                "VALUES(?,?,?,?,?,?,?)",
                (self.manual_id, "Same", "Same\nBody", "blue", 20, 21, 0),
            )
            db.commit()
        with closing(sqlite3.connect(self.old / "notes.db")) as db:
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) "
                "VALUES(?,?,?,?,?,?)",
                (self.old_id, "Older", "Older text", "gray", 30, 31),
            )
            db.commit()

    def test_v6_auto_title_round_trip(self) -> None:
        """Preserve an explicit automatic-title state across a portable note bundle."""
        bundle = self.root / "automatic.stickies"
        exchange.share_note(self.new, self.auto_id, bundle)
        with zipfile.ZipFile(bundle) as archive:
            note = json.loads(archive.read("manifest.json"))["note"]
        self.assertEqual(note["auto_title"], 1)
        self.assertEqual(len(note), 19)
        self.assertEqual(exchange.import_note(self.other, bundle, True), "Note imported")
        with closing(sqlite3.connect(self.other / "notes.db")) as db:
            self.assertEqual(
                db.execute("SELECT auto_title,title FROM notes WHERE id=?", (self.auto_id,))
                .fetchone(), (1, "First line"),
            )
        self.assertEqual(exchange.import_note(self.other, bundle, True),
                         "Note already present")

    def test_v5_manual_bundle_remains_compatible(self) -> None:
        """Produce the old 16-field bundle for manual active titles."""
        bundle = self.root / "manual.stickies"
        exchange.share_note(self.new, self.manual_id, bundle)
        with zipfile.ZipFile(bundle) as archive:
            note = json.loads(archive.read("manifest.json"))["note"]
        self.assertNotIn("auto_title", note)
        self.assertEqual(len(note), 16)
        self.assertEqual(exchange.import_note(self.old, bundle, True), "Note imported")
        self.assertEqual(exchange.import_note(self.other, bundle, True), "Note imported")
        with closing(sqlite3.connect(self.other / "notes.db")) as db:
            self.assertEqual(
                db.execute("SELECT auto_title FROM notes WHERE id=?", (self.manual_id,))
                .fetchone(), (0,),
            )

    def test_v5_input_imports_to_v6_as_manual(self) -> None:
        """Old note records never infer a manual title's state from its text."""
        bundle = self.root / "legacy.stickies"
        exchange.share_note(self.old, self.old_id, bundle)
        self.assertEqual(exchange.import_note(self.other, bundle, True), "Note imported")
        with closing(sqlite3.connect(self.other / "notes.db")) as db:
            self.assertEqual(
                db.execute("SELECT auto_title FROM notes WHERE id=?", (self.old_id,))
                .fetchone(), (0,),
            )

    def test_downgrade_rejects_auto_title_without_mutation(self) -> None:
        """Never silently discard title-mode semantics on an older database."""
        bundle = self.root / "automatic.stickies"
        exchange.share_note(self.new, self.auto_id, bundle)
        with self.assertRaisesRegex(exchange.ExchangeError, "Upgrade Stickies"):
            exchange.import_note(self.old, bundle, True)
        with closing(sqlite3.connect(self.old / "notes.db")) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM notes").fetchone(), (1,))

    def test_v6_backup_contains_title_mode(self) -> None:
        """Backup v6 records with the same integrity guarantees as earlier schemas."""
        archive = self.root / "copy.backup"
        backup.create_backup(self.new, archive)
        backup.verify_backup(archive)
        with zipfile.ZipFile(archive) as contents:
            metadata = json.loads(contents.read("manifest.json"))
        self.assertEqual(metadata["schema_version"], 6)


if __name__ == "__main__":
    unittest.main()
