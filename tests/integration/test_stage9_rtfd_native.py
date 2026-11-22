"""Verify lossless Majoris native style payload inside portable RTFD directories."""

from __future__ import annotations

from contextlib import closing
import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_rtfd", ROOT / "tools/stickies_rtfd.py")
assert SPEC and SPEC.loader
rtfd = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rtfd)


class RtfdNativeTests(unittest.TestCase):
    """Check native inline-asset mapping without weakening RTF compatibility."""

    def setUp(self) -> None:
        """Create one note with an inline image and custom Unicode formatting."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.data = self.base / "store"
        (self.data / "attachments").mkdir(parents=True)
        self.note_id = str(uuid.uuid4())
        self.image_id = str(uuid.uuid4())
        self.content = "Résumé \uFFFC and 漢字"
        self.formatting = (
            f"7:8:image_{self.image_id}_480\n"
            "0:6:face_DejaVu%20Sans\n"
            "0:6:rgb_88aa66\n"
            "0:6:point_38\n"
        )
        with closing(sqlite3.connect(self.data / "notes.db")) as db:
            db.executescript("""
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY, title TEXT, content TEXT,
                    formatting TEXT, status INTEGER
                );
                CREATE TABLE attachments (
                    id TEXT, note_id TEXT, display_name TEXT, mime_type TEXT
                );
            """)
            db.execute(
                "INSERT INTO notes VALUES(?,?,?,?,?)",
                (self.note_id, "Test", self.content, self.formatting, 0),
            )
            db.execute(
                "INSERT INTO attachments VALUES(?,?,?,?)",
                (self.image_id, self.note_id, "photo.png", "image/png"),
            )
            db.commit()
        (self.data / "attachments" / f"{self.image_id}.asset").write_bytes(
            b"a bounded fake image payload"
        )
        self.package = self.base / "native.rtfd"

    def test_rtfd_preserves_native_positions_and_styles(self) -> None:
        """Return inline placement and source IDs for remapping by Vala importer."""
        rtfd.export_note(self.data, self.note_id, self.package)
        text, fallback, files = rtfd.inspect_package(self.package)
        self.assertIn("Résumé", text)
        self.assertEqual(len(files), 1)
        native = rtfd.read_native_note(self.package, files)
        self.assertIsNotNone(native)
        content, formatting, identities = native
        self.assertEqual(content, self.content)
        self.assertEqual(formatting, self.formatting)
        self.assertEqual(identities[files[0].name], self.image_id)
        self.assertTrue((self.package / "TXT.rtf").exists())
        output = subprocess.run(
            [sys.executable, str(ROOT / "tools/stickies_rtfd.py"),
             "metadata", str(self.package)],
            text=True, capture_output=True, timeout=10, check=True,
        ).stdout
        self.assertIn("@content\t", output)
        self.assertIn("@formatting\t", output)
        self.assertIn(self.image_id, output)

    def test_rtfd_rejects_unowned_image_reference(self) -> None:
        """Reject image styles that do not reference one of this package's assets."""
        rtfd.export_note(self.data, self.note_id, self.package)
        path = self.package / "majoris.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["native"]["formatting"] = self.formatting.replace(
            self.image_id, str(uuid.uuid4())
        )
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)

    def test_rtfd_rejects_duplicate_metadata_keys(self) -> None:
        """Reject ambiguous JSON rather than silently using its last native payload."""
        rtfd.export_note(self.data, self.note_id, self.package)
        manifest = self.package / "majoris.json"
        data = manifest.read_text(encoding="utf-8")
        manifest.write_text(
            data.replace('"format":"majoris-rtfd-1",',
                         '"format":"majoris-rtfd-1","format":"majoris-rtfd-1",'),
            encoding="utf-8",
        )
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)

    def test_rtfd_rejects_duplicate_original_image_identity(self) -> None:
        """Require a one-to-one mapping between manifest assets and private IDs."""
        rtfd.export_note(self.data, self.note_id, self.package)
        path = self.package / "majoris.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["attachments"][0]["source_id"] = "not-a-uuid"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)


if __name__ == "__main__":
    unittest.main()
