"""Exercise the optional TextEdit fixture verifier with a constructed package."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TextEditFixtureHarnessTests(unittest.TestCase):
    """Keep fixture qualification deterministic without inventing AppKit data."""

    def test_constructed_example_passes_expected_properties(self) -> None:
        """Ensure a correctly declared local package can be inspected."""
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "Example.rtfd"
            package.mkdir()
            (package / "TXT.rtf").write_bytes(
                br"{\rtf1\pard\li720 Example\par}"
            )
            expected = Path(directory) / "expected.json"
            expected.write_text(json.dumps({
                "required_styles": ["para-li_720"],
                "attachments": [],
                "inline_images": 0,
                "text": "Example\n",
            }), encoding="utf-8")
            command = [
                sys.executable,
                str(ROOT / "tools" / "stickies_textedit_qualify.py"),
                str(package), "--expected", str(expected),
            ]
            completed = subprocess.run(
                command, text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(completed.stdout)
            self.assertIn("para-li_720", report["paragraph_styles"])
            expected.write_text(json.dumps({
                "required_styles": ["para-li_1440"],
            }), encoding="utf-8")
            completed = subprocess.run(
                command, text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("lost required formatting", completed.stderr)


if __name__ == "__main__":
    unittest.main()
