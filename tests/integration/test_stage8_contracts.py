"""Static integration contracts for Stage 8's new user-facing paths."""

from __future__ import annotations

import re
import unittest
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]


class Stage8Contracts(unittest.TestCase):
    """Protect bounded desktop and text interchange behavior across modules."""

    def test_rtf_importer_is_installed_and_wired(self) -> None:
        """Require helper, Vala service, and GUI action to agree on its name."""
        meson = (ROOT / "meson.build").read_text()
        install = (ROOT / "debian" / "majoris-stickies.install").read_text()
        src = (ROOT / "src" / "meson.build").read_text()
        service = (ROOT / "src/services/rtf-importer.vala").read_text()
        editor = (ROOT / "src/gtk/note-window.vala").read_text()
        self.assertIn("'services/rtf-importer.vala'", src)
        self.assertIn("rename: 'majoris-stickies-rtf-import'", meson)
        self.assertIn("usr/bin/majoris-stickies-rtf-import", install)
        self.assertIn('"majoris-stickies-rtf-import"', service)
        self.assertIn("RtfImporter.import_note", editor)
        self.assertIn("Import Rich Text (RTF)", editor)

    def test_shell_bridge_and_extension_match(self) -> None:
        """Match compositor methods and restrict lookup to Stickies windows."""
        extension = (
            ROOT / "shell/majoris-stickies@majoris.org/extension.js"
        ).read_text()
        bridge = (ROOT / "src/services/shell-window-bridge.vala").read_text()
        app = (ROOT / "src/app/application.vala").read_text()
        for method in ("ToggleSticky", "RestoreLayout"):
            self.assertIn(f'<method name="{method}"', extension)
            self.assertIn(f'"{method}"', bridge)
        self.assertIn("this._registered.get(windowId)", extension)
        self.assertIn("this._findWindow(windowId)", extension)
        self.assertIn("MAX_DESKTOP_NOTE_WINDOWS = 64", app)
        self.assertIn("const MAX_WINDOWS = 64", extension)
        self.assertIn("note_windows.size >= MAX_DESKTOP_NOTE_WINDOWS", app)

    def test_interactive_checklist_and_persistent_find_dialog(self) -> None:
        """Require reusable commands and match-case control in the GTK resource."""
        editor = (ROOT / "src/gtk/note-window.vala").read_text()
        commands = (ROOT / "src/gtk/text-edit-commands.vala").read_text()
        document = ElementTree.parse(ROOT / "data/text-tools.ui")
        ids = {element.get("id") for element in document.iter("object")}
        self.assertIn("find_case_sensitive", ids)
        self.assertIn("toggle_checklist_item", editor)
        self.assertIn("toggle_checklist_item", commands)
        self.assertIn("match_case.active", editor)
        self.assertIn("Gtk.TextSearchFlags.CASE_INSENSITIVE", commands)
        self.assertIn("var window = new Gtk.Window ();", editor)

    def test_image_decoding_remains_imagekit_only_and_lazy(self) -> None:
        """Do not eagerly decode image files or add a competing loader."""
        editor = (ROOT / "src/gtk/note-window.vala").read_text()
        self.assertIn("var viewer = new ImageKit.ImageView ();", editor)
        self.assertIn('expander.notify["expanded"]', editor)
        self.assertIsNone(re.search(r"Gdk\\.Texture\\.new_from_file", editor))


if __name__ == "__main__":
    unittest.main()
