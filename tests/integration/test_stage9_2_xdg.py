"""Verify that installed local tools follow the application's XDG data path."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TOOL_FILES = ("stickies_backup.py", "stickies_exchange.py", "stickies_reminders.py")


def load_tool(name: str):
    """Load one tool exactly as it is shipped, with no package installation."""
    spec = importlib.util.spec_from_file_location(name.removesuffix(".py"), ROOT / "tools" / name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class XdgPathTests(unittest.TestCase):
    """Ensure helpers and their CLI defaults agree with GLib's data directory."""

    def test_absolute_xdg_directory_used_by_all_tools(self) -> None:
        """Do not silently read a different user's store when XDG_DATA_HOME is set."""
        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(os.environ, {"XDG_DATA_HOME": temporary}):
                for name in TOOL_FILES:
                    with self.subTest(tool=name):
                        module = load_tool(name)
                        expected = Path(temporary) / "majoris" / "stickies"
                        self.assertEqual(module.default_data_dir(), expected)
                        variable = "DEFAULT_DATA_DIR" if name == "stickies_backup.py" else "DATA_DIR"
                        self.assertEqual(getattr(module, variable), expected)

    def test_empty_and_relative_xdg_directory_fall_back(self) -> None:
        """Reject a non-absolute XDG path without interpreting it relative to cwd."""
        for value in ("", "relative/path"):
            with self.subTest(xdg=value), patch.dict(os.environ, {"XDG_DATA_HOME": value}):
                for name in TOOL_FILES:
                    module = load_tool(name)
                    self.assertEqual(
                        module.default_data_dir(),
                        Path.home() / ".local" / "share" / "majoris" / "stickies",
                    )


if __name__ == "__main__":
    unittest.main()
