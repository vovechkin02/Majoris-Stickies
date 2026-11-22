"""Guard Stage 7 packaging and RTF menu/source contract consistency."""

from __future__ import annotations

import configparser
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ReleaseContracts(unittest.TestCase):
    """Check installation maps without requiring the native SDK."""

    def test_every_vala_module_is_built(self) -> None:
        """Prevent accidental omission of cohesive source modules from Meson."""
        source_list = (ROOT / "src/meson.build").read_text(encoding="utf-8")
        for source in (ROOT / "src").rglob("*.vala"):
            self.assertIn(f"'{source.relative_to(ROOT / 'src').as_posix()}'", source_list)

    def test_export_is_wired_to_menu_and_debian_package(self) -> None:
        """Keep helper executable, service, and user-visible command together."""
        editor = (ROOT / "src/gtk/note-window.vala").read_text(encoding="utf-8")
        service = (ROOT / "src/services/rtf-exporter.vala").read_text(encoding="utf-8")
        meson = (ROOT / "meson.build").read_text(encoding="utf-8")
        install = (ROOT / "debian/majoris-stickies.install").read_text(encoding="utf-8")
        self.assertIn("Export Rich Text (RTF)", editor)
        self.assertIn("RtfExporter.export_note", editor)
        self.assertIn('"majoris-stickies-rtf"', service)
        self.assertIn("rename: 'majoris-stickies-rtf'", meson)
        self.assertIn("usr/bin/majoris-stickies-rtf", install)

    def test_desktop_actions_preserve_command_contract(self) -> None:
        """Ensure existing launchers keep matching single-instance commands."""
        document = configparser.ConfigParser(interpolation=None)
        document.read(ROOT / "data/com.majoris.stickies.desktop")
        application = (ROOT / "src/app/application.vala").read_text(encoding="utf-8")
        for name in ("NewNote", "CaptureScreenshot", "ShowNotes"):
            section = document[f"Desktop Action {name}"]
            arguments = section["Exec"].split()
            self.assertEqual(arguments[0], "majoris-stickies")
            self.assertIn(arguments[-1], application)

    def test_reminder_is_marked_only_after_submission(self) -> None:
        """Avoid treating an unsent reminder as irrevocably delivered."""
        application = (ROOT / "src/app/application.vala").read_text(encoding="utf-8")
        delivery = application.split("private void deliver_due_reminders ()", 1)[1]
        delivery = delivery.split("protected override void shutdown ()", 1)[0]
        self.assertLess(
            delivery.index("send_notification (note.id, notification)"),
            delivery.index("store.mark_reminder_notified (note.id, now_us)"),
        )


if __name__ == "__main__":
    unittest.main()
