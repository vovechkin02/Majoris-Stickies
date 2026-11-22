"""Offline recovery regression cases using a real temporary SQLite database."""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from stickies_backup import BackupError, create_backup, restore_backup, verify_backup

NOTE_ID = "d9fa3a03-3fb0-40d5-acf7-e92f00c45bb1"
ASSET_ID = "ec59a732-0931-4220-9ddf-770f3356fa98"


class RecoveryTests(unittest.TestCase):
    """Verify complete and intentionally damaged application backups."""

    def setUp(self) -> None:
        """Create a Stage 3 database with one attachment and live WAL activity."""
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.data_dir = self.root / "data"
        self.data_dir.mkdir()
        self.database_path = self.data_dir / "notes.db"
        self.connection = sqlite3.connect(self.database_path)
        self.addCleanup(self.connection.close)
        self.connection.executescript(
            """PRAGMA journal_mode=WAL;
            PRAGMA foreign_keys=ON;
            CREATE TABLE notes (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                color TEXT NOT NULL,
                created_at_us INTEGER NOT NULL,
                updated_at_us INTEGER NOT NULL,
                formatting TEXT NOT NULL DEFAULT '',
                collapsed INTEGER NOT NULL DEFAULT 0,
                floating INTEGER NOT NULL DEFAULT 0,
                translucent INTEGER NOT NULL DEFAULT 0,
                window_width INTEGER NOT NULL DEFAULT 370,
                window_height INTEGER NOT NULL DEFAULT 330,
                visible INTEGER NOT NULL DEFAULT 0,
                source_url TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE attachments (
                id TEXT PRIMARY KEY NOT NULL,
                note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                display_name TEXT NOT NULL,
                mime_type TEXT NOT NULL
            );
            PRAGMA user_version=3;
            """
        )
        self.connection.execute(
            "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) "
            "VALUES(?,?,?,?,?,?)",
            (NOTE_ID, "Important", "Résumé: 道", "yellow", 1, 2),
        )
        self.connection.execute(
            "INSERT INTO attachments VALUES(?,?,?,?)",
            (ASSET_ID, NOTE_ID, "picture.png", "image/png"),
        )
        self.connection.commit()
        (self.data_dir / "attachments").mkdir()
        (self.data_dir / "attachments" / f"{ASSET_ID}.asset").write_bytes(b"image-bytes")
        (self.data_dir / "window-positions.json").write_text(
            '{"example": {"x": -1200, "y": 10}}', encoding="utf-8"
        )
        self.archive_path = self.root / "notes.stickies.zip"

    def test_complete_roundtrip(self) -> None:
        """Persist note contents and attachments from a WAL-backed source."""
        create_backup(self.data_dir, self.archive_path)
        verify_backup(self.archive_path)
        target = self.root / "restored"
        restore_backup(self.archive_path, target)
        with sqlite3.connect(target / "notes.db") as saved:
            self.assertEqual(
                saved.execute("SELECT content FROM notes WHERE id=?", (NOTE_ID,)).fetchone(),
                ("Résumé: 道",),
            )
        self.assertEqual(
            (target / "attachments" / f"{ASSET_ID}.asset").read_bytes(),
            b"image-bytes",
        )
        self.assertEqual(
            json.loads((target / "window-positions.json").read_text())["example"]["x"],
            -1200,
        )

    def test_stage5_reminder_backup_roundtrip(self) -> None:
        """Preserve v4 reminder values and assets through verified recovery."""
        self.connection.executescript(
            "ALTER TABLE notes ADD COLUMN remind_at_us INTEGER NOT NULL DEFAULT 0;"
            "ALTER TABLE notes ADD COLUMN reminder_notified_at_us INTEGER NOT NULL DEFAULT 0;"
            "PRAGMA user_version=4;"
        )
        self.connection.execute(
            "UPDATE notes SET remind_at_us=?,reminder_notified_at_us=? WHERE id=?",
            (1_800_000_000_000_000, 0, NOTE_ID),
        )
        self.connection.commit()
        create_backup(self.data_dir, self.archive_path)
        verify_backup(self.archive_path)
        target = self.root / "stage5-restored"
        restore_backup(self.archive_path, target)
        with sqlite3.connect(target / "notes.db") as database:
            self.assertEqual(database.execute("PRAGMA user_version").fetchone(), (4,))
            self.assertEqual(
                database.execute("SELECT remind_at_us FROM notes").fetchone(),
                (1_800_000_000_000_000,),
            )
        self.assertEqual((target / "attachments" / f"{ASSET_ID}.asset").read_bytes(),
                         b"image-bytes")

    def test_backup_existing_stage1_database(self) -> None:
        """Preserve pre-migration Stage 1 notes without requiring a Stage 4 app launch."""
        self.connection.close()
        for suffix in ("", "-shm", "-wal"):
            (self.data_dir / f"notes.db{suffix}").unlink(missing_ok=True)
        (self.data_dir / "attachments" / f"{ASSET_ID}.asset").unlink()
        with sqlite3.connect(self.database_path) as database:
            database.execute(
                "CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, content TEXT, "
                "color TEXT, created_at_us INTEGER, updated_at_us INTEGER)"
            )
            database.execute(
                "INSERT INTO notes VALUES(?,?,?,?,?,?)",
                (NOTE_ID, "Legacy", "Old text", "yellow", 1, 2),
            )
            database.execute("PRAGMA user_version=1")
        create_backup(self.data_dir, self.archive_path)
        verify_backup(self.archive_path)
        target = self.root / "stage1-restored"
        restore_backup(self.archive_path, target)
        with sqlite3.connect(target / "notes.db") as database:
            self.assertEqual(database.execute("PRAGMA user_version").fetchone(), (1,))
            self.assertEqual(database.execute("SELECT title FROM notes").fetchone(),
                             ("Legacy",))

    def test_refuses_overwrite(self) -> None:
        """Never overwrite an archive or existing note database during restore."""
        create_backup(self.data_dir, self.archive_path)
        with self.assertRaises(BackupError):
            create_backup(self.data_dir, self.archive_path)
        with self.assertRaises(BackupError):
            restore_backup(self.archive_path, self.data_dir)
        self.assertTrue(self.database_path.is_file())

    def test_rejects_missing_attachment(self) -> None:
        """Reject incomplete backups instead of silently losing files."""
        (self.data_dir / "attachments" / f"{ASSET_ID}.asset").unlink()
        with self.assertRaises(BackupError):
            create_backup(self.data_dir, self.archive_path)

    def test_rejects_corrupt_content(self) -> None:
        """Detect byte-level tampering even when the ZIP remains readable."""
        create_backup(self.data_dir, self.archive_path)
        with zipfile.ZipFile(self.archive_path, "a") as archive:
            archive.writestr("unexpected/file.txt", "surprise")
        with self.assertRaises(BackupError):
            verify_backup(self.archive_path)

    def test_rejects_forged_digest(self) -> None:
        """Reject a plausible-looking archive with altered manifest metadata."""
        create_backup(self.data_dir, self.archive_path)
        with zipfile.ZipFile(self.archive_path, "r") as original:
            content = {name: original.read(name) for name in original.namelist()}
        manifest = json.loads(content["manifest.json"])
        manifest["files"]["notes.db"]["sha256"] = "0" * 64
        content["manifest.json"] = json.dumps(manifest).encode()
        with zipfile.ZipFile(self.archive_path, "w") as damaged:
            for name, data in content.items():
                damaged.writestr(name, data)
        with self.assertRaises(BackupError):
            verify_backup(self.archive_path)

    def test_restore_rejects_zip_slip(self) -> None:
        """Disallow archive entries that escape the intended restore directory."""
        create_backup(self.data_dir, self.archive_path)
        with zipfile.ZipFile(self.archive_path, "a") as archive:
            archive.writestr("../../not-a-note", "attack")
        with self.assertRaises(BackupError):
            restore_backup(self.archive_path, self.root / "restored")
        self.assertFalse((self.root / "restored").exists())


if __name__ == "__main__":
    unittest.main()
