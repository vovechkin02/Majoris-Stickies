"""Contract checks for local source capture and removal of service scaffolding."""

from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalSourceContracts(unittest.TestCase):
    """Check wiring and privacy constraints not covered by offline RTF tests."""

    def test_paste_wires_detect_once_per_user_action(self) -> None:
        """A user paste, rather than a clipboard watcher, requests attribution."""
        editor = (ROOT / "src/gtk/note-window.vala").read_text(encoding="utf-8")
        self.assertIn("body_view.paste_clipboard.connect", editor)
        self.assertIn("ClipboardSourceCapture.detect", editor)
        self.assertIn("expected_revision != clipboard_revision", editor)
        self.assertIn('note.source_url != ""', editor)
        self.assertIn("repository.set_source_url (note.id, detected)", editor)
        self.assertIn("clipboard_changed_id = 0", editor)
        self.assertIn("GLib.SignalHandler.disconnect (get_clipboard ()", editor)

    def test_clipboard_mimes_are_explicit_and_bounded(self) -> None:
        """Only selected MIME formats participate and no browser session is queried."""
        service = (ROOT / "src/services/clipboard-source-capture.vala").read_text()
        model = (ROOT / "src/core/source-link.vala").read_text()
        self.assertIn("MAX_READ_BYTES = 64 * 1024", service)
        self.assertIn('"text/x-moz-url", "text/uri-list", "text/html"', service)
        self.assertIn('"text/plain;charset=utf-8", "text/plain"', service)
        self.assertIn("SourceLink.from_clipboard_bytes (", service)
        self.assertIn("used + size > MAX_READ_BYTES", service)
        self.assertIn("MAX_PROVENANCE_BYTES = 64 * 1024", model)
        self.assertIn("A source must be an HTTP or HTTPS URL", model)
        self.assertIn("if (candidate != \"\")", model)
        self.assertNotIn("org.mozilla", service)
        self.assertNotIn("org.chromium", service)

    def test_unused_proprietary_qualification_scaffolding_removed(self) -> None:
        """Keep standard file formats but remove platform-only fixture tooling."""
        for name in (
            "tools/macos/qualify_textedit_roundtrip.sh",
            "tools/stickies_textedit_qualify.py",
            "docs/qualification/textedit-case-matrix.json",
            "docs/stage-9-13-qualification.md",
            "tests/integration/test_stage9_13_textedit_qualification.py",
            "tests/integration/test_stage9_12_textedit_harness.py",
        ):
            with self.subTest(name=name):
                self.assertFalse((ROOT / name).exists())
        self.assertTrue((ROOT / "tools/stickies_rtfd.py").exists())
        self.assertTrue((ROOT / "tools/stickies_rtf_import.py").exists())
        self.assertEqual(
            (ROOT / "meson.build").read_text().split("version: '")[1].split("'")[0],
            "0.9.14",
        )


if __name__ == "__main__":
    unittest.main()
