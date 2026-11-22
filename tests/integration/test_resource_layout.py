"""Validate that XML templates and resource paths match their Vala bindings."""

from __future__ import annotations

import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


class ResourceLayoutTests(unittest.TestCase):
    """Check static UI contracts without requiring a graphical display."""

    @classmethod
    def setUpClass(cls) -> None:
        """Resolve the data directory supplied by Meson's integration test."""
        cls.data_dir = Path(sys.argv[1])

    def test_resource_manifest_lists_all_ui_assets(self) -> None:
        """Require every referenced template and style file to be packaged."""
        root = ET.parse(self.data_dir / "com.majoris.stickies.gresource.xml").getroot()
        filenames = {node.text for node in root.iter("file")}
        self.assertEqual(
            filenames,
            {"manager-window.ui", "note-window.ui", "note-colors.css"},
        )
        for name in filenames:
            self.assertTrue((self.data_dir / name).is_file(), name)

    def test_manager_template_contains_expected_controls(self) -> None:
        """Require the manager's card list, search, and toolbar controls."""
        tree = ET.parse(self.data_dir / "manager-window.ui")
        template = tree.find("template")
        self.assertIsNotNone(template)
        self.assertEqual(template.attrib["class"], "StickiesManagerWindow")
        ids = {element.get("id") for element in tree.iter("object")}
        self.assertTrue(
            {"notes_flow", "new_button", "search_entry", "empty_label", "toast_overlay"}
            <= ids
        )

    def test_template_child_bindings_match_source(self) -> None:
        """Reject XML controls that are absent from the matching Vala template."""
        import re

        root = self.data_dir.parent / "src" / "gtk"
        for window in ("manager-window", "note-window"):
            source = (root / f"{window}.vala").read_text(encoding="utf-8")
            document = ET.parse(self.data_dir / f"{window}.ui")
            ids = {item.get("id") for item in document.iter("object")}
            bindings = re.findall(
                r"\[GtkChild\]\s+private unowned [A-Za-z.]+ ([a-z_]+);",
                source,
            )
            self.assertTrue(bindings, window)
            self.assertTrue(set(bindings) <= ids, f"{window}: missing {set(bindings) - ids}")

    def test_palette_css_covers_all_colors(self) -> None:
        """Require a semantic note-paper CSS rule for each palette option."""
        colors = {"yellow", "pink", "green", "blue", "purple", "orange", "teal", "gray"}
        css = (self.data_dir / "note-colors.css").read_text(encoding="utf-8")
        for color in colors:
            self.assertIn(f".note-paper.note-{color}", css)
            self.assertIn(f".note-card.note-{color}", css)
            self.assertIn(f".color-chip.note-{color}", css)

    def test_note_template_contains_expected_controls(self) -> None:
        """Require separate title, body, color, and save-status controls."""
        tree = ET.parse(self.data_dir / "note-window.ui")
        template = tree.find("template")
        self.assertIsNotNone(template)
        self.assertEqual(template.attrib["class"], "StickiesNoteWindow")
        ids = {element.get("id") for element in tree.iter("object")}
        self.assertTrue(
            {
                "title_entry",
                "body_view",
                "paper_box",
                "color_button",
                "save_label",
                "delete_button",
            }
            <= ids
        )


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
