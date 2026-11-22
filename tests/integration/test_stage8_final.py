"""Regression tests for the final Stage 8 metadata and editor-safety update."""

from __future__ import annotations

from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
NOTE_ID = "87654321-2222-3333-4444-123456789abc"
ASSET_ID = "87654321-2222-3333-4444-123456789abd"


def load_rtfd():
    """Import the actual installed-compatible RTFD utility for behavioral checks."""
    path = ROOT / "tools/stickies_rtfd.py"
    spec = importlib.util.spec_from_file_location("stickies_rtfd_final", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rtfd = load_rtfd()


class Stage8FinalTests(unittest.TestCase):
    """Test manifest safety, existing-note portability and import protections."""

    def make_package(self, root: Path) -> Path:
        """Export one note and an image with a non-ASCII original filename."""
        data = root / "data"
        (data / "attachments").mkdir(parents=True)
        with closing(sqlite3.connect(data / "notes.db")) as db:
            db.execute("CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, "
                       "content TEXT, formatting TEXT, status INTEGER)")
            db.execute("CREATE TABLE attachments (id TEXT, note_id TEXT, "
                       "display_name TEXT, mime_type TEXT)")
            db.execute("INSERT INTO notes VALUES (?,?,?,?,?)",
                       (NOTE_ID, "Note", "Text", "", 0))
            db.execute("INSERT INTO attachments VALUES (?,?,?,?)",
                       (ASSET_ID, NOTE_ID, "café sketch.png", "image/png"))
            db.commit()
        (data / "attachments" / (ASSET_ID + ".asset")).write_bytes(
            b"\x89PNG\r\n\x1a\n"
        )
        dest = root / "note.rtfd"
        rtfd.export_note(data, NOTE_ID, dest)
        return dest

    def test_metadata_restores_original_name_and_type(self):
        """Machine-readable metadata preserves original names without raw paths."""
        with tempfile.TemporaryDirectory() as tmp:
            source = self.make_package(Path(tmp))
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/stickies_rtfd.py"),
                 "metadata", str(source)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("caf%C3%A9%20sketch.png\timage/png", result.stdout)
            _, _, assets = rtfd.inspect_package(source)
            self.assertEqual(rtfd.read_attachment_metadata(source, assets),
                             {"attachment-0001.png": ("café sketch.png", "image/png")})

    def test_reject_manifest_traversal_duplicate_and_type_spoofing(self):
        """Reject malformed metadata before it can be imported."""
        with tempfile.TemporaryDirectory() as tmp:
            source = self.make_package(Path(tmp))
            manifest = source / "majoris.json"
            original = json.loads(manifest.read_text())
            for name, mime in (("../secret", "image/png"),
                               ("x.png", "application/pdf")):
                modified = json.loads(json.dumps(original))
                modified["attachments"][0]["name"] = name
                modified["attachments"][0]["mime"] = mime
                manifest.write_text(json.dumps(modified))
                with self.assertRaises(rtfd.RtfdError):
                    rtfd.inspect_package(source)
            modified = json.loads(json.dumps(original))
            modified["attachments"].append(modified["attachments"][0])
            manifest.write_text(json.dumps(modified))
            with self.assertRaises(rtfd.RtfdError):
                rtfd.inspect_package(source)

    def test_legacy_rtfd_without_manifest(self):
        """Older RTFD packages remain readable using generated display names."""
        with tempfile.TemporaryDirectory() as tmp:
            source = self.make_package(Path(tmp))
            (source / "majoris.json").unlink()
            _, _, files = rtfd.inspect_package(source)
            self.assertEqual(rtfd.read_attachment_metadata(source, files),
                             {"attachment-0001.png":
                              ("attachment-0001.png", "image/png")})

    def test_plain_import_has_editor_revision_guard(self):
        """A pending import cannot silently overwrite later text edits."""
        source = (ROOT / "src/gtk/note-window.vala").read_text()
        section = source.split("private async void import_text_async", 1)[1].split(
            "private void choose_export", 1
        )[0]
        self.assertIn("editor_revision != initial_revision", section)
        self.assertIn("editor_text () != previous_text", section)
        self.assertIn("RichTextCodec.serialize", section)


if __name__ == "__main__":
    unittest.main()
