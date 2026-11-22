"""Verify Stage 8 completion: dynamic RTF tables and bounded RTFD packages."""

from __future__ import annotations

import importlib.util
from contextlib import closing
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_tool(name: str):
    """Load one repository-owned tool through its actual source filename."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rtf = load_tool("stickies_rtf_import")
rtfd = load_tool("stickies_rtfd")
NOTE_ID = "87654321-2222-3333-4444-123456789abc"
ASSET_ID = "87654321-2222-3333-4444-123456789abd"


class Stage8CompletionTests(unittest.TestCase):
    """Protect actual interchange behavior and a known desktop action regression."""

    def test_rtf_uses_declared_font_and_color_tables(self) -> None:
        """Font zero can be Courier and color index one can be blue."""
        source = (
            br"{\rtf1\ansi{\fonttbl{\f0\fmodern Courier New;}{\f1\fswiss Arial;}}"
            br"{\colortbl;\red0\green0\blue255;\red255\green0\blue0;}"
            br"\f0\cf1 C\f1\cf2 R}"
        )
        text, styles = rtf.RtfReader().parse(source)
        self.assertEqual(text, "CR")
        for expected in (
            "0:1:font-monospace\n", "0:1:text-blue\n",
            "1:2:font-sans\n", "1:2:text-red\n",
        ):
            self.assertIn(expected, styles)

    def test_rtf_skips_unknown_color_instead_of_mislabeling(self) -> None:
        """An unrelated index must not silently become a familiar palette color."""
        source = (
            br"{\rtf1\ansi{\colortbl;\red255\green200\blue0;}\cf1 Yellow}"
        )
        text, styles = rtf.RtfReader().parse(source)
        self.assertEqual(text, "Yellow")
        self.assertNotIn("text-red", styles)

    def test_rtfd_export_import_with_attachment(self) -> None:
        """Export one new RTFD folder and re-read the text and managed image."""
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            data = base / "local"
            assets = data / "attachments"
            assets.mkdir(parents=True)
            with closing(sqlite3.connect(data / "notes.db")) as connection:
                connection.execute(
                    "CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, "
                    "content TEXT, formatting TEXT, status INTEGER)"
                )
                connection.execute(
                    "CREATE TABLE attachments (id TEXT, note_id TEXT, "
                    "display_name TEXT, mime_type TEXT)"
                )
                connection.execute(
                    "INSERT INTO notes VALUES (?,?,?,?,?)",
                    (NOTE_ID, "Sample", "Hello world", "0:5:bold\n", 0),
                )
                connection.execute(
                    "INSERT INTO attachments VALUES (?,?,?,?)",
                    (ASSET_ID, NOTE_ID, "photo.png", "image/png"),
                )
                connection.commit()
            (assets / (ASSET_ID + ".asset")).write_bytes(b"\x89PNG\r\n\x1a\n")
            output = base / "sample.rtfd"
            rtfd.export_note(data, NOTE_ID, output)
            text, formatting, included = rtfd.inspect_package(output)
            self.assertIn("Hello world", text)
            self.assertIn("bold", formatting)
            self.assertEqual([item.name for item in included], ["attachment-0001.png"])
            self.assertEqual(included[0].read_bytes(), b"\x89PNG\r\n\x1a\n")
            manifest = json.loads((output / "majoris.json").read_text())
            self.assertEqual(manifest["attachments"][0]["name"], "photo.png")
            with self.assertRaises(rtfd.RtfdError):
                rtfd.export_note(data, NOTE_ID, output)
            self.assertTrue((output / "TXT.rtf").exists())

    def test_rtfd_command_loads_installed_sibling_tools(self) -> None:
        """Meson-renamed command filenames remain importable by the RTFD tool."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            renamed = {
                "stickies_rtf.py": "majoris-stickies-rtf",
                "stickies_rtf_import.py": "majoris-stickies-rtf-import",
                "stickies_rtfd.py": "majoris-stickies-rtfd",
            }
            for source, target in renamed.items():
                shutil.copyfile(ROOT / "tools" / source, folder / target)
            result = subprocess.run(
                [sys.executable, str(folder / "majoris-stickies-rtfd"), "--help"],
                capture_output=True, timeout=5, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_pdf_page_parameter_is_bounded(self) -> None:
        """Reject page zero and pages beyond the maximum before running Poppler."""
        preview = load_tool("stickies_pdf_preview")
        for page in (0, 251, -1):
            with self.subTest(page=page):
                with self.assertRaises(preview.PdfPreviewError):
                    preview.render_page(Path("unused.pdf"), page)

    def test_pdf_second_page_with_real_poppler(self) -> None:
        """Render page two and reject nonexistent page three, when available."""
        if shutil.which("pdftoppm") is None:
            self.skipTest("Poppler not installed")
        preview = load_tool("stickies_pdf_preview")
        texts = (b"BT /F1 18 Tf 20 40 Td (Page one) Tj ET",
                 b"BT /F1 18 Tf 20 40 Td (Page two) Tj ET")
        objects = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
            (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] "
             b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Length %d >>\nstream\n" % len(texts[0]) + texts[0] + b"\nendstream",
            (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] "
             b"/Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>"),
            b"<< /Length %d >>\nstream\n" % len(texts[1]) + texts[1] + b"\nendstream",
        ]
        data = b"%PDF-1.4\n"
        offsets = []
        for index, obj in enumerate(objects, 1):
            offsets.append(len(data))
            data += b"%d 0 obj\n" % index + obj + b"\nendobj\n"
        position = len(data)
        data += b"xref\n0 8\n0000000000 65535 f \n"
        for offset in offsets:
            data += b"%010d 00000 n \n" % offset
        data += b"trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % position
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "two.pdf"
            pdf.write_bytes(data)
            image = preview.render_page(pdf, 2)
            try:
                self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
            finally:
                image.unlink(missing_ok=True)
                image.parent.rmdir()
            with self.assertRaises(preview.PdfPreviewError):
                preview.render_page(pdf, 3)

    def test_shell_translucency_is_scoped_to_registered_notes(self) -> None:
        """The extension must not change arbitrary compositor windows."""
        source = (
            ROOT / "shell/majoris-stickies@majoris.org/extension.js"
        ).read_text()
        self.assertIn("SetTranslucent(windowId, enabled)", source)
        self.assertIn("this._registered.has(windowId)", source)
        self.assertIn("actor.opacity = enabled ? 220 : 255", source)

    def test_rtfd_rejects_links_and_unexpected_assets(self) -> None:
        """Reject external symlinks and untrusted package filenames."""
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "safe.rtfd"
            source.mkdir()
            (source / "TXT.rtf").write_bytes(b"{\\rtf1 Plain}")
            (source / "attachment-0001.png").symlink_to(base / "outside")
            with self.assertRaises(rtfd.RtfdError):
                rtfd.inspect_package(source)
            (source / "attachment-0001.png").unlink()
            (source / "script.sh").write_text("echo bad")
            with self.assertRaises(rtfd.RtfdError):
                rtfd.inspect_package(source)

    def test_desktop_show_notes_command_opens_individual_windows(self) -> None:
        """The desktop action must call the note-window path, not only activate."""
        application = (ROOT / "src/app/application.vala").read_text()
        self.assertIn('else if (option == "--show-notes")', application)
        self.assertIn('show_all_note_windows ();', application)

    def test_editor_import_has_revision_guard(self) -> None:
        """A completed asynchronous import may not overwrite intervening edits."""
        editor = (ROOT / "src/gtk/note-window.vala").read_text()
        self.assertIn("editor_revision != revision_before_import", editor)
        self.assertIn("editor_revision != initial_revision", editor)


if __name__ == "__main__":
    unittest.main()
