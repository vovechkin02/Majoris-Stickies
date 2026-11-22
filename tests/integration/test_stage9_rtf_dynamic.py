"""Check the bounded RTF fallback for dynamically styled Stage 8 notes."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stickies_rtf", ROOT / "tools/stickies_rtf.py")
assert SPEC and SPEC.loader
rtf = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rtf)


class DynamicRtfTests(unittest.TestCase):
    """Avoid losing valid styles while rejecting untrusted formatting."""

    def test_custom_font_color_point_size_and_list(self) -> None:
        """Emit declared RTF tables instead of relying on fixed color/font indexes."""
        text = "Résumé and notes"
        styles = (
            "0:6:face_DejaVu%20Sans\n"
            "0:6:rgb_aabbcc\n"
            "0:6:point_38\n"
            "0:6:list-bullet\n"
        )
        rendered = rtf.make_rtf("Note", text, styles)
        self.assertIn(br"\red170\green187\blue204;", rendered)
        self.assertIn(br"\fs76 ", rendered)
        self.assertIn(b"DejaVu Sans", rendered)
        self.assertIn(br"\u233?", rendered)

    def test_inline_image_is_a_safe_external_text_fallback(self) -> None:
        """Never invent executable RTF objects for a private image attachment."""
        text = "A \uFFFC image"
        token = "image_12345678-1234-1234-1234-123456789abc_480"
        rendered = rtf.make_rtf("Image note", text, f"2:3:{token}\n")
        self.assertIn(b"Image note", rendered)
        self.assertNotIn(br"\object", rendered)
        self.assertNotIn(br"\pict", rendered)

    def test_out_of_range_tokens_are_rejected(self) -> None:
        """Reject forged size, width, and RGB values without exporting invalid RTF."""
        for style in ("point_999", "rgb_ffffxz",
                      "image_12345678-1234-1234-1234-123456789abc_999"):
            with self.subTest(style=style):
                with self.assertRaises(rtf.RtfExportError):
                    rtf.make_rtf("Title", "X", f"0:1:{style}\n")


if __name__ == "__main__":
    unittest.main()
