"""Check bounded RTF-to-Stickies import and Stage 7 export compatibility."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_tool(name: str):
    """Load the exact repository helper without requiring installation."""
    source = ROOT / "tools" / name
    spec = importlib.util.spec_from_file_location(name.replace(".", "_"), source)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


importer = load_tool("stickies_rtf_import.py")
exporter = load_tool("stickies_rtf.py")


class Stage8RtfImportTests(unittest.TestCase):
    """Exercise actual conversion, rejection, and local command output."""

    def test_import_exported_text_and_unicode(self) -> None:
        """Import Stage 7 exports with non-ASCII, emoji and nested styles."""
        data = exporter.make_rtf(
            "Title", "Hi \U0001f642 caf\u00e9!", "0:2:bold\n3:7:italic\n"
        )
        text, formatting = importer.RtfReader().parse(data)
        self.assertEqual(text, "Title\n\nHi \U0001f642 caf\u00e9!")
        self.assertIn("7:9:bold\n", formatting)
        self.assertIn("10:14:italic\n", formatting)

    def test_skips_binary_metadata_and_unsupported_destinations(self) -> None:
        """Avoid leaking font tables, image contents and field instructions."""
        source = (b"{\\rtf1\\ansi{\\fonttbl{\\f0 Arial;}}"
                  b"Visible{\\*\\unknown hidden}{\\pict\\pngblip deadbeef} end}")
        text, _ = importer.RtfReader().parse(source)
        self.assertEqual(text, "Visible end")

    def test_imports_styles_and_escaped_controls(self) -> None:
        """Preserve ordinary bold/italics and literal escape characters."""
        text, formatting = importer.RtfReader().parse(
            b"{\\rtf1 A \\b bold\\b0  \\i italic\\i0  \\{x\\}\\\\}"
        )
        self.assertEqual(text, "A bold italic {x}\\")
        self.assertIn("2:6:bold\n", formatting)
        self.assertIn("7:13:italic\n", formatting)

    def test_rejects_bad_structure_and_excessive_nesting(self) -> None:
        """Refuse malformed RTF and unbounded group recursion."""
        sources = (
            b"plain text", b"{\\rtf1 unterminated", b"{\\rtf1 broken}}",
            b"{\\rtf1 " + b"{" * 65 + b"}" * 65 + b"}",
            b"{\\rtf1 a\x00b}",
            b"{\\rtf1 \\'zz}",
            b"{\\rtf1 " + b"a" * (importer.MAX_OUTPUT_BYTES + 1) + b"}",
        )
        for source in sources:
            with self.subTest(source=source[:40]):
                with self.assertRaises(importer.RtfImportError):
                    importer.RtfReader().parse(source)

    def test_rejects_embedded_transfer_delimiter(self) -> None:
        """Keep subprocess transfer framing unambiguous."""
        with self.assertRaises(importer.RtfImportError):
            importer.RtfReader().parse(b"{\\rtf1 a\x1eb}")

    def test_subprocess_outputs_separated_body_and_spans(self) -> None:
        """Exercise the installed-helper contract without shell invocation."""
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.rtf"
            source.write_bytes(b"{\\rtf1 Hello \\b world}")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools" / "stickies_rtf_import.py"),
                    str(source),
                ],
                check=True, capture_output=True, timeout=5,
            )
            self.assertEqual(completed.stdout.decode(), "Hello world\x1e6:11:bold\n")

    def test_rejects_symlink_input(self) -> None:
        """Never follow symbolic links to arbitrary private files."""
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.rtf"
            source.write_bytes(b"{\\rtf1 Hello}")
            link = Path(temporary) / "link.rtf"
            link.symlink_to(source)
            with self.assertRaises(importer.RtfImportError):
                importer.import_rtf(link)


if __name__ == "__main__":
    unittest.main()
