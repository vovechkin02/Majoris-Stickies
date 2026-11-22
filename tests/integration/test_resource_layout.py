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
            {"notes_flow", "new_button", "arrange_button", "search_entry", "empty_label", "toast_overlay"}
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

    def test_stage3_controls_present(self) -> None:
        """Check screenshot actions, source controls, and manager filters."""
        manager = ET.parse(self.data_dir / "manager-window.ui")
        note = ET.parse(self.data_dir / "note-window.ui")
        manager_ids = {node.get("id") for node in manager.iter("object")}
        note_ids = {node.get("id") for node in note.iter("object")}
        self.assertTrue(
            {"screenshot_button", "color_filter", "sort_dropdown", "list_toggle", "count_label"}
            <= manager_ids
        )
        self.assertTrue({"screenshot_button", "source_button"} <= note_ids)

    def test_desktop_actions_match_application(self) -> None:
        """Require supported single-instance command-line routes in the launcher."""
        import configparser

        desktop = configparser.ConfigParser(interpolation=None)
        desktop.read(self.data_dir / "com.majoris.stickies.desktop")
        commands = {
            "NewNote": "--new-note",
            "CaptureScreenshot": "--capture-screenshot",
            "ShowNotes": "--show-notes",
        }
        actions = desktop["Desktop Entry"]["Actions"].strip(";").split(";")
        self.assertEqual(actions, list(commands))
        application = (self.data_dir.parent / "src/app/application.vala").read_text()
        for name, command in commands.items():
            self.assertEqual(desktop[f"Desktop Action {name}"]["Exec"],
                             f"majoris-stickies {command}")
            self.assertIn(command, application)

    def test_accessible_control_names(self) -> None:
        """Require meaningful GTK4 accessible labels on the editor and controls."""
        required = {
            "manager-window.ui": {
                "new_button", "screenshot_button", "arrange_button", "search_entry",
                "color_filter", "sort_dropdown", "list_toggle", "load_more_button",
            },
            "note-window.ui": {
                "title_entry", "body_view", "color_button", "more_button",
                "manager_button", "duplicate_button", "delete_button",
            },
        }
        for filename, names in required.items():
            document = ET.parse(self.data_dir / filename)
            by_id = {node.get("id"): node for node in document.iter("object")}
            for name in names:
                accessible = by_id[name].find("accessibility/property[@name='label']")
                self.assertIsNotNone(accessible, f"{filename}: {name}")
                self.assertTrue(accessible.text.strip(), f"{filename}: {name}")

    def test_stage4_card_pagination_contract(self) -> None:
        """Require a bounded card page and a connected Load More control."""
        document = ET.parse(self.data_dir / "manager-window.ui")
        ids = {node.get("id") for node in document.iter("object")}
        self.assertIn("load_more_button", ids)
        source = (self.data_dir.parent / "src/gtk/manager-window.vala").read_text()
        self.assertIn("CARD_PAGE_SIZE = 60", source)
        self.assertIn("load_more_button.clicked.connect", source)
        self.assertIn("append_cards (requested_card_count)", source)

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
                "more_button",
                "attachments_box",
                "bold_button",
                "italic_button",
                "underline_button",
                "strike_button",
                "mono_button",
                "large_button",
                "small_button",
            }
            <= ids
        )


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
