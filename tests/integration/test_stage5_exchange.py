"""Exercise opt-in portable sharing and conflict-safe folder synchronization."""

from __future__ import annotations

import importlib.util
from contextlib import closing, contextmanager
import sqlite3
import tempfile
import unittest
import uuid
import zipfile
from unittest.mock import patch
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "tools/stickies_exchange.py"
SPEC = importlib.util.spec_from_file_location("stickies_exchange", SCRIPT)
assert SPEC and SPEC.loader
exchange = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exchange)


@contextmanager
def _database(path: Path):
    """Commit and close every test database deterministically."""
    with closing(sqlite3.connect(path)) as connection:
        with connection:
            yield connection


class ExchangeTests(unittest.TestCase):
    """Protect note ownership and data preservation during exchange operations."""

    def setUp(self) -> None:
        """Create two isolated Stage 5 stores and one shared offline folder."""
        bus_check = patch.object(exchange, "_application_is_running", return_value=False)
        bus_check.start()
        self.addCleanup(bus_check.stop)
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        base = Path(self.scratch.name)
        self.first = base / "first"
        self.second = base / "second"
        self.shared = base / "shared"
        for directory in (self.first, self.second, self.shared):
            directory.mkdir()
        for directory in (self.first, self.second):
            with _database(directory / "notes.db") as connection:
                connection.executescript("""
                    PRAGMA user_version=4;
                    PRAGMA foreign_keys=ON;
                    CREATE TABLE notes (
                        id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL,
                        content TEXT NOT NULL, color TEXT NOT NULL,
                        created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL,
                        formatting TEXT NOT NULL DEFAULT '', collapsed INTEGER NOT NULL DEFAULT 0,
                        floating INTEGER NOT NULL DEFAULT 0, translucent INTEGER NOT NULL DEFAULT 0,
                        window_width INTEGER NOT NULL DEFAULT 370,
                        window_height INTEGER NOT NULL DEFAULT 330,
                        visible INTEGER NOT NULL DEFAULT 0,
                        source_url TEXT NOT NULL DEFAULT '',
                        remind_at_us INTEGER NOT NULL DEFAULT 0,
                        reminder_notified_at_us INTEGER NOT NULL DEFAULT 0
                    );
                    CREATE TABLE attachments (
                        id TEXT PRIMARY KEY NOT NULL,
                        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL, mime_type TEXT NOT NULL
                    );
                """)
        self.note_id = str(uuid.uuid4())
        with _database(self.first / "notes.db") as connection:
            connection.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) "
                "VALUES(?,?,?,?,?,?)",
                (self.note_id, "A note", "Résumé / 日本語", "yellow", 10, 11),
            )
        self.asset_id = str(uuid.uuid4())
        (self.first / "attachments").mkdir()
        (self.first / "attachments" / f"{self.asset_id}.asset").write_bytes(b"sample image")
        with _database(self.first / "notes.db") as connection:
            connection.execute(
                "INSERT INTO attachments VALUES(?,?,?,?)",
                (self.asset_id, self.note_id, "picture.png", "image/png"),
            )

    def sync(self, directory: Path) -> dict[str, int]:
        """Run an explicitly confirmed offline merge."""
        return exchange.sync_folder(directory, self.shared, app_closed=True)

    def test_share_preserves_only_selected_note_and_assets(self) -> None:
        """Verify bundle metadata, Unicode text, SHA-256 and asset bytes."""
        output = Path(self.scratch.name) / "one.stickies"
        exchange.share_note(self.first, self.note_id, output)
        note, assets, digest = exchange._read_bundle(output)
        self.assertEqual(note["content"], "Résumé / 日本語")
        self.assertEqual(next(iter(assets.values()))[1], b"sample image")
        self.assertEqual(len(digest), 64)
        self.assertEqual(len(note), 19)  # Normalized with v6 title-mode default.
        self.assertEqual((note["status"], note["pinned"]), (0, 0))
        with zipfile.ZipFile(output) as archive:
            import json
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(len(manifest["note"]), 16)

    def test_import_single_shared_note_preserves_existing_edits(self) -> None:
        """Receive a share once, then keep a conflicting local revision separately."""
        output = Path(self.scratch.name) / "shared-note.stickies"
        exchange.share_note(self.first, self.note_id, output)
        self.assertEqual(exchange.import_note(self.second, output, app_closed=True),
                         "Note imported")
        self.assertEqual(exchange.import_note(self.second, output, app_closed=True),
                         "Note already present")
        with _database(self.second / "notes.db") as connection:
            connection.execute("UPDATE notes SET content='Local work'")
        self.assertEqual(exchange.import_note(self.second, output, app_closed=True),
                         "Imported as a new conflict copy")
        with _database(self.second / "notes.db") as connection:
            self.assertEqual({row[0] for row in connection.execute("SELECT content FROM notes")},
                             {"Local work", "Résumé / 日本語"})

    def test_share_never_overwrites_an_existing_file(self) -> None:
        """Avoid accidentally replacing a note bundle with a chosen filename."""
        output = Path(self.scratch.name) / "already.stickies"
        output.write_bytes(b"keep this exact data")
        with self.assertRaises(exchange.ExchangeError):
            exchange.share_note(self.first, self.note_id, output)
        self.assertEqual(output.read_bytes(), b"keep this exact data")

    def test_rejects_extra_zip_member_on_import(self) -> None:
        """Prevent untrusted bundle paths from being accepted on import."""
        output = Path(self.scratch.name) / "tampered.stickies"
        exchange.share_note(self.first, self.note_id, output)
        with zipfile.ZipFile(output, "a") as archive:
            archive.writestr("../../escape.txt", "malicious")
        with self.assertRaises(exchange.ExchangeError):
            exchange.import_note(self.second, output, app_closed=True)
        self.assertFalse((self.second / "notes.db").with_suffix(".malicious").exists())

    def test_sync_round_trip_and_remote_edit(self) -> None:
        """Publish, receive, update on another device, then receive the edit."""
        self.assertEqual(self.sync(self.first)["published"], 1)
        self.assertEqual(self.sync(self.second)["received"], 1)
        with _database(self.second / "notes.db") as connection:
            self.assertEqual(connection.execute("SELECT content FROM notes").fetchone()[0],
                             "Résumé / 日本語")
            connection.execute("UPDATE notes SET content='Updated',updated_at_us=22")
        self.assertEqual(self.sync(self.second)["published"], 1)
        self.assertEqual(self.sync(self.first)["received"], 1)
        with _database(self.first / "notes.db") as connection:
            self.assertEqual(connection.execute("SELECT content FROM notes").fetchone()[0],
                             "Updated")

    def test_conflict_creates_an_independent_local_note(self) -> None:
        """Never silently overwrite divergent text from two machines."""
        self.sync(self.first)
        self.sync(self.second)
        with _database(self.first / "notes.db") as connection:
            connection.execute("UPDATE notes SET content='Local',updated_at_us=31")
        with _database(self.second / "notes.db") as connection:
            connection.execute("UPDATE notes SET content='Remote',updated_at_us=32")
        self.sync(self.second)
        result = self.sync(self.first)
        self.assertEqual(result["conflicts"], 1)
        with _database(self.first / "notes.db") as connection:
            self.assertEqual({row[0] for row in connection.execute("SELECT content FROM notes")},
                             {"Local", "Remote"})
            self.assertEqual(connection.execute("SELECT count(*) FROM notes").fetchone()[0], 2)
        self.assertEqual(self.sync(self.first)["conflicts"], 0)

    def test_rejects_tampered_asset_without_mutating_database(self) -> None:
        """Reject invalid hashes and preserve existing note collections."""
        self.sync(self.first)
        bundle = self.shared / f"{self.note_id}.stickies"
        with zipfile.ZipFile(bundle) as archive:
            manifest = archive.read("manifest.json")
        with zipfile.ZipFile(bundle, "w") as archive:
            archive.writestr("manifest.json", manifest)
            archive.writestr(f"assets/{self.asset_id}.asset", b"tampered")
        with self.assertRaises(exchange.ExchangeError):
            self.sync(self.second)
        with _database(self.second / "notes.db") as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM notes").fetchone()[0], 0)

    def test_never_runs_without_closed_app_confirmation(self) -> None:
        """Make the offline synchronization safety boundary explicit."""
        with self.assertRaises(exchange.ExchangeError):
            exchange.sync_folder(self.first, self.shared, app_closed=False)

    def test_unchanged_presentation_does_not_trigger_conflicts(self) -> None:
        """Window geometry and delivery receipts are machine-local metadata."""
        self.sync(self.first)
        self.sync(self.second)
        with _database(self.second / "notes.db") as connection:
            connection.execute(
                "UPDATE notes SET window_width=930,visible=1,reminder_notified_at_us=42"
            )
        result = self.sync(self.second)
        self.assertEqual(result["unchanged"], 1)


if __name__ == "__main__":
    unittest.main()
