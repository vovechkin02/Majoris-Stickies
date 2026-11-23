"""Exercise safe AppKit NeXTGraphic imports and Majoris RTFD export fidelity."""

from __future__ import annotations

from contextlib import closing
import importlib.util
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_rtfd", ROOT / "tools/stickies_rtfd.py")
assert SPEC is not None and SPEC.loader is not None
rtfd = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rtfd)


class ExternalRtfdCompatibilityTests(unittest.TestCase):
    """Test real attachment-reference semantics without relying on native GTK."""

    def setUp(self) -> None:
        """Create a secure portable RTFD directory for each independent case."""
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.package = self.root / "External.rtfd"
        self.package.mkdir(mode=0o700)
        self.picture = self.package / "Pasted Graphic.png"
        self.picture.write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(25))

    def _rtf(self, data: bytes) -> None:
        """Write one bounded Apple RTF stream into the expected file."""
        (self.package / "TXT.rtf").write_bytes(data)

    def test_external_package_with_spaces_and_inline_position(self) -> None:
        """Decode sibling filenames and retain exact Unicode text locations."""
        self._rtf(
            b"{\\rtf1\\ansi Before {{\\NeXTGraphic Pasted Graphic.png "
            b"\\width7200 \\height4800}\\'ac} after}"
        )
        text, formatting, assets = rtfd.inspect_package(self.package)
        self.assertEqual(len(assets), 1)
        self.assertEqual(assets[0].name, "Pasted Graphic.png")
        self.assertIn("Before", text)
        external = rtfd._external_note(self.package, assets)
        self.assertIsNotNone(external)
        body, styles, identifiers = external
        self.assertEqual(body, "Before \ufffc after")
        self.assertIn("7:8:image_", styles)
        self.assertIn("_480\n", styles)
        self.assertIn("Pasted Graphic.png", identifiers)
        command = subprocess.run(
            [sys.executable, str(ROOT / "tools/stickies_rtfd.py"),
             "metadata", str(self.package)],
            capture_output=True, text=True, timeout=10, check=True,
        )
        self.assertIn("@content\t", command.stdout)
        self.assertIn("@formatting\t", command.stdout)
        self.assertIn(identifiers["Pasted Graphic.png"], command.stdout)

    def test_utf8_filename_with_rtf_hex_escapes(self) -> None:
        """Accept ordinary, UTF-8-encoded Apple attachment filenames."""
        self.picture.rename(self.package / "Caf\u00e9.png")
        self._rtf(
            b"{\\rtf1 x {{\\NeXTGraphic Caf\\'c3\\'a9.png "
            b"\\width2400}\\'ac} y}"
        )
        assets = rtfd.inspect_package(self.package)[2]
        body, styles, _ = rtfd._external_note(self.package, assets)
        self.assertEqual(body, "x \ufffc y")
        self.assertRegex(
            styles, r"^2:3:image_[0-9a-f-]{36}_160\n$"
        )

    def test_multiple_images_and_apple_attachment_properties(self) -> None:
        """Keep each external inline asset in its original character position."""
        (self.package / "Second.tif").write_bytes(b"II*\x00" + bytes(16))
        self._rtf(
            b"{\\rtf1 First {{\\NeXTGraphic Pasted Graphic.png "
            b"\\width3600 \\height1800 \\appleattachmentpadding0 "
            b"\\appleembedtype0 \\appleaqc}\\'ac} "
            b"and {{\\NeXTGraphic Second.tif \\width7200}" + bytes([0xac]) + b"}}"
        )
        assets = rtfd.inspect_package(self.package)[2]
        body, styles, identities = rtfd._external_note(self.package, assets)
        self.assertEqual(body, "First \ufffc and \ufffc")
        self.assertEqual(body.count("\ufffc"), 2)
        self.assertEqual(len(identities), 2)
        self.assertIn("6:7:image_", styles)
        self.assertIn("12:13:image_", styles)
        self.assertIn("_240\n", styles)
        self.assertIn("_480\n", styles)

    def test_external_package_without_inline_images_remains_compatible(self) -> None:
        """Import normal RTFD text and its unrelated safe attachments intact."""
        self._rtf(b"{\\rtf1 Ordinary \\b rich\\b0  text}")
        text, formatting, assets = rtfd.inspect_package(self.package)
        self.assertEqual(text, "Ordinary rich text")
        self.assertIn("bold", formatting)
        self.assertEqual([file.name for file in assets], ["Pasted Graphic.png"])
        self.assertIsNone(rtfd._external_note(self.package, assets))
        command = subprocess.run(
            [sys.executable, str(ROOT / "tools/stickies_rtfd.py"),
             "metadata", str(self.package)],
            capture_output=True, text=True, timeout=10, check=True,
        )
        self.assertNotIn("@content", command.stdout)
        self.assertIn("Pasted%20Graphic.png", command.stdout)

    def test_refuses_malformed_or_missing_references(self) -> None:
        """Fail closed on missing assets or unsupported Apple graphic grammar."""
        for token in (
            b"{{\\NeXTGraphic /etc/passwd \\width7200}\\'ac}",
            b"{{\\NeXTGraphic Missing.png \\width7200}\\'ac}",
            b"{{\\NeXTGraphic Pasted Graphic.png \\width7200}",
        ):
            with self.subTest(token=token):
                self._rtf(b"{\\rtf1 " + token + b"}")
                with self.assertRaises((rtfd.RtfdError, rtfd.RtfImportError)):
                    rtfd.inspect_package(self.package)

    def test_rejects_symlinks_and_nested_directory(self) -> None:
        """Never follow outside assets or nested package path components."""
        self._rtf(b"{\\rtf1 Hello}")
        extra = self.package / "Outside.png"
        extra.symlink_to(self.picture)
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)

    def test_export_writes_apple_graphic_record_and_native_payload(self) -> None:
        """Export both AppKit-compatible visual placement and lossless metadata."""
        store = self.root / "store"
        (store / "attachments").mkdir(parents=True)
        identity = str(uuid.uuid4())
        image_id = str(uuid.uuid4())
        with closing(sqlite3.connect(store / "notes.db")) as db:
            db.executescript("""
                CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, content TEXT,
                    formatting TEXT, status INTEGER);
                CREATE TABLE attachments (id TEXT, note_id TEXT,
                    display_name TEXT, mime_type TEXT);
            """)
            db.execute(
                "INSERT INTO notes VALUES (?,?,?,?,0)",
                (identity, "Note", "A\ufffcB", f"1:2:image_{image_id}_480\n"),
            )
            db.execute(
                "INSERT INTO attachments VALUES (?,?,?,?)",
                (image_id, identity, "Photo.png", "image/png"),
            )
            db.commit()
        (store / "attachments" / f"{image_id}.asset").write_bytes(
            b"\x89PNG\r\n\x1a\n" + bytes(25)
        )
        output = self.root / "Export.rtfd"
        rtfd.export_note(store, identity, output)
        rtf = (output / "TXT.rtf").read_bytes()
        self.assertIn(b"\\NeXTGraphic attachment-0001.png \\width7200", rtf)
        inspected = rtfd.inspect_package(output)
        self.assertEqual(len(inspected[2]), 1)
        native = rtfd.read_native_note(output, inspected[2])
        self.assertIsNotNone(native)
        self.assertEqual(native[0], "A\ufffcB")
        self.assertEqual(native[1], f"1:2:image_{image_id}_480\n")


if __name__ == "__main__":
    unittest.main()
