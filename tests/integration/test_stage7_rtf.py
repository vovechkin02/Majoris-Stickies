"""Exercise RTF output, limits, Unicode and destination file guarantees."""

from __future__ import annotations

import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "tools" / "stickies_rtf.py"
spec = importlib.util.spec_from_file_location("stickies_rtf", MODULE)
assert spec is not None and spec.loader is not None
rtf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rtf)


class RtfTests(unittest.TestCase):
    """Validate safe, reproducible RTF interchange output."""

    def test_export_ascii_and_nested_styles(self) -> None:
        """Emit readable RTF and balanced style groups for overlap."""
        data = rtf.make_rtf("Title", "Hello", "0:5:bold\n1:3:italic\n")
        self.assertIn(b"\\rtf1", data)
        self.assertIn(b"\\b ", data)
        self.assertIn(b"\\i ", data)
        self.assertEqual(data.count(b"{"), data.count(b"}"))
        self.assertIn(b"Hello", rtf.make_rtf("Title", "Hello", ""))

    def test_overlapping_intervals(self) -> None:
        """Retain a style when overlapping spans have different endpoints."""
        data = rtf.make_rtf("T", "abcdef", "0:4:bold\n2:6:bold\n")
        self.assertIn(b"\\b ef", data)
        self.assertEqual(data.count(b"{"), data.count(b"}"))

    def test_escape_markup_and_unicode(self) -> None:
        """Escape RTF metacharacters and generate signed UTF-16 sequences."""
        data = rtf.make_rtf("A{B}\\", "\u00e9\U0001f642\n\t", "")
        self.assertIn(b"A\\{B\\}\\\\", data)
        self.assertIn(b"\\u233?", data)
        self.assertIn(b"\\u-10179?\\u-8638?", data)
        self.assertIn(b"\\par", data)
        self.assertIn(b"\\tab", data)

    def test_reject_invalid_styles_and_ranges(self) -> None:
        """Do not trust malformed persisted formatting records."""
        for formatting in ("0:6:bold\n", "0:1:script\n", "0:-1:bold\n", "x:1:bold\n"):
            with self.subTest(formatting=formatting):
                with self.assertRaises(rtf.RtfExportError):
                    rtf.make_rtf("Note", "a", formatting)

    def test_bounded_input(self) -> None:
        """Reject oversized notes before creating a file."""
        with self.assertRaises(rtf.RtfExportError):
            rtf.make_rtf("Note", "a" * (rtf.MAX_NOTE_BYTES + 1), "")

    def test_export_reads_db_and_never_overwrites(self) -> None:
        """Require active note status and preserve an existing RTF file."""
        with tempfile.TemporaryDirectory() as directory:
            data_dir = Path(directory)
            identifier = "6b2de3e7-066b-4c45-9992-015b3486f9d9"
            with sqlite3.connect(data_dir / "notes.db") as database:
                database.execute(
                    "CREATE TABLE notes (id TEXT, title TEXT, content TEXT, "
                    "formatting TEXT, status INTEGER)"
                )
                database.execute(
                    "INSERT INTO notes VALUES (?, 'A note', 'Body', '0:4:bold\n', 0)",
                    (identifier,),
                )
            destination = data_dir / "export.rtf"
            rtf.export_note(data_dir, identifier, destination)
            self.assertIn(b"\\b Body", destination.read_bytes())
            with self.assertRaises(rtf.RtfExportError):
                rtf.export_note(data_dir, identifier, destination)
            self.assertIn(b"Body", destination.read_bytes())

    def test_reject_invalid_and_archived_note(self) -> None:
        """Reject invalid identity and notes excluded from active exports."""
        with self.assertRaises(rtf.RtfExportError):
            rtf.export_note(Path("/nowhere"), "../etc/passwd", Path("/tmp/escape.rtf"))
        with tempfile.TemporaryDirectory() as directory:
            data_dir = Path(directory)
            identifier = "6b2de3e7-066b-4c45-9992-015b3486f9d9"
            with sqlite3.connect(data_dir / "notes.db") as database:
                database.execute(
                    "CREATE TABLE notes (id TEXT, title TEXT, content TEXT, "
                    "formatting TEXT, status INTEGER)"
                )
                database.execute(
                    "INSERT INTO notes VALUES (?, 'Archived', 'Body', '', 1)",
                    (identifier,),
                )
            with self.assertRaises(rtf.RtfExportError):
                rtf.export_note(data_dir, identifier, data_dir / "note.rtf")


if __name__ == "__main__":
    unittest.main()
