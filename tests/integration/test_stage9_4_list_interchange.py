"""Confirm nested-list depth survives portable exchange and bounded RTF fallback."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_tool(name: str):
    """Import a script under its own module name for isolated contract testing."""
    path = ROOT / "tools" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class NestedListCompatibility(unittest.TestCase):
    """Retain the existing textual fallback while validating hierarchy tokens."""

    def test_exchange_accepts_six_levels(self) -> None:
        """All supported depths survive a portable note-format validation."""
        exchange = load_tool("stickies_exchange")
        for depth in range(1, 7):
            with self.subTest(depth=depth):
                self.assertTrue(exchange._style_supported(f"list-depth-{depth}"))
        for forged in ("list-depth-0", "list-depth-7", "list-depth-01", "list-depth-1:evil"):
            self.assertFalse(exchange._style_supported(forged))

    def test_rtf_fallback_preserves_text_without_objects(self) -> None:
        """The text fallback remains readable when hierarchy tags are present."""
        exporter = load_tool("stickies_rtf")
        body = "        • Nested list item"
        rtf = exporter.make_rtf("List", body, f"0:{len(body)}:list-depth-2\n")
        self.assertIn(b"Nested list item", rtf)
        self.assertNotIn(br"\object", rtf)
        self.assertNotIn(br"\pict", rtf)
        with self.assertRaises(exporter.RtfExportError):
            exporter.make_rtf("List", body, f"0:{len(body)}:list-depth-99\n")


if __name__ == "__main__":
    unittest.main()
