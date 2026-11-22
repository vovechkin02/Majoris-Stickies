"""Qualify portable Stage 8 rich styles and inline media through share and sync."""

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


class InlineExchangeTests(unittest.TestCase):
    """Protect cross-machine inline media identity and rich text fidelity."""

    def setUp(self) -> None:
        """Create isolated version-5 stores and a folder for offline synchronization."""
        patcher = patch.object(exchange, "_application_is_running", return_value=False)
        patcher.start()
        self.addCleanup(patcher.stop)
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.base = Path(scratch.name)
        self.first = self.base / "first"
        self.second = self.base / "second"
        self.shared = self.base / "shared"
        self.shared.mkdir()
        for store in (self.first, self.second):
            store.mkdir()
            with closing(sqlite3.connect(store / "notes.db")) as db:
                db.executescript("""
                    PRAGMA user_version=5;
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
                    );
                    CREATE TABLE attachments (
                        id TEXT PRIMARY KEY NOT NULL,
                        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                        display_name TEXT NOT NULL, mime_type TEXT NOT NULL
                    );
                """)
        self.note_id = str(uuid.uuid4())
        self.image_id = str(uuid.uuid4())
        self.payload = b"unique attached image content"
        self.formatting = (
            f"2:3:image_{self.image_id}_240\n"
            "0:3:face_DejaVu%20Sans\n"
            "0:3:rgb_9a02ff\n"
            "0:3:point_38\n"
            "0:3:list-bullet\n"
        )
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute(
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us,formatting) "
                "VALUES(?,?,?,?,?,?,?)",
                (self.note_id, "Inline", "A \uFFFC B", "blue", 10, 11, self.formatting),
            )
            db.execute(
                "INSERT INTO attachments VALUES(?,?,?,?)",
                (self.image_id, self.note_id, "a.png", "image/png"),
            )
            db.commit()
        (self.first / "attachments").mkdir()
        (self.first / "attachments" / f"{self.image_id}.asset").write_bytes(self.payload)

    def _note(self, store: Path) -> tuple[str, str]:
        """Return saved text and formatting from an isolated database."""
        with closing(sqlite3.connect(store / "notes.db")) as db:
            return db.execute(
                "SELECT content,formatting FROM notes WHERE id=?", (self.note_id,)
            ).fetchone()

    def test_share_import_remaps_and_preserves_formatting(self) -> None:
        """Use destination-managed asset identities without losing inline placement."""
        bundle = self.base / "note.stickies"
        exchange.share_note(self.first, self.note_id, bundle)
        self.assertEqual(exchange.import_note(self.second, bundle, True), "Note imported")
        content, imported = self._note(self.second)
        self.assertEqual(content, "A \uFFFC B")
        with closing(sqlite3.connect(self.second / "notes.db")) as db:
            transferred_id = db.execute("SELECT id FROM attachments").fetchone()[0]
        self.assertNotEqual(transferred_id, self.image_id)
        self.assertIn(f"2:3:image_{transferred_id}_240", imported)
        self.assertIn("face_DejaVu%20Sans", imported)
        self.assertIn("rgb_9a02ff", imported)
        self.assertEqual(
            (self.second / "attachments" / f"{transferred_id}.asset").read_bytes(),
            self.payload,
        )
        self.assertEqual(exchange.import_note(self.second, bundle, True), "Note already present")

    def test_sync_roundtrip_has_no_false_conflicts(self) -> None:
        """Ensure different local asset UUIDs do not cause repeated sync conflicts."""
        self.assertEqual(exchange.sync_folder(self.first, self.shared, True)["published"], 1)
        self.assertEqual(exchange.sync_folder(self.second, self.shared, True)["received"], 1)
        self.assertEqual(exchange.sync_folder(self.second, self.shared, True)["unchanged"], 1)
        self.assertEqual(exchange.sync_folder(self.first, self.shared, True)["unchanged"], 1)

    def test_reject_orphan_and_invalid_image_anchor(self) -> None:
        """Reject missing or non-object media spans before creating a shared bundle."""
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute("UPDATE notes SET formatting=?", (
                f"2:3:image_{uuid.uuid4()}_240\n",))
            db.commit()
        with self.assertRaises(exchange.ExchangeError):
            exchange.share_note(self.first, self.note_id, self.base / "invalid.stickies")
        with closing(sqlite3.connect(self.first / "notes.db")) as db:
            db.execute("UPDATE notes SET content='Hello', formatting=?", (
                f"2:3:image_{self.image_id}_240\n",))
            db.commit()
        with self.assertRaises(exchange.ExchangeError):
            exchange.share_note(self.first, self.note_id, self.base / "not-an-object.stickies")

    def test_reject_malformed_dynamic_styles(self) -> None:
        """Bound font URLs, RGB colors, point sizes, and paths in style tokens."""
        good = ["face_DejaVu%20Sans", "point_8", "point_72", "rgb_012abc"]
        bad = ["point_007", "point_73", "rgb_12ggff", "face_%2e%2e%2f",
               "face_Foo:Bar", "image_../../escape_240", "face_%FF"]
        for style in good:
            with self.subTest(style=style):
                self.assertTrue(exchange._style_supported(style))
        for style in bad:
            with self.subTest(style=style):
                self.assertFalse(exchange._style_supported(style))


if __name__ == "__main__":
    unittest.main()
