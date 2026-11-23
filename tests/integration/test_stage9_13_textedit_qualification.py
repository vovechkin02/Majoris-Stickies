"""Qualify deterministic RTFD comparisons without inventing macOS evidence."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "stickies_textedit_qualify.py"
PIXEL = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
    b"\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\x0bIDATx\x9cc```\x00\x02\x00\x00\x05\x00\x01"
    b"\xa5\xf6E@\x00\x00\x00\x00IEND\xaeB`\x82"
)


class TextEditQualificationTests(unittest.TestCase):
    """Test stable comparison and provenance contracts without an AppKit runtime."""

    def setUp(self) -> None:
        """Create bounded private local fixtures for source-only regression tests."""
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def package(
        self, name: str, *, filename: str = "Photo.png", width: int = 2400,
        indent: int = 720, pixel: bytes = PIXEL, no_image: bool = False,
    ) -> Path:
        """Create a deliberately synthetic RTFD with one inline raster image."""
        folder = self.root / (name + ".rtfd")
        folder.mkdir()
        if no_image:
            body = br"{\rtf1\ansi\pard\li720 Hello\par}"
        else:
            body = (
                rf"{{\rtf1\ansi\pard\li{indent} Hello".encode("ascii")
                + br" {{\NeXTGraphic " + filename.encode("ascii")
                + rf" \width{width}".encode("ascii") + br"}\'ac}\par}"
            )
            (folder / filename).write_bytes(pixel)
        (folder / "TXT.rtf").write_bytes(body)
        return folder

    def run_tool(self, *arguments: object) -> subprocess.CompletedProcess[str]:
        """Invoke the real command-line tool without importing private state."""
        return subprocess.run(
            [sys.executable, str(TOOL), *(str(item) for item in arguments)],
            text=True, capture_output=True, timeout=20,
        )

    def test_unchanged_comparison_and_matrix(self) -> None:
        """Equivalent constructed packages pass but are not labeled genuine."""
        source = self.package("original")
        target = self.package("majoris")
        resaved = self.package("resaved")
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["equivalent"])
        self.assertTrue(report["visual_review_required"])
        result = self.run_tool("matrix", source, target, resaved)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["equivalent"])
        self.assertFalse(report["authentic_textedit_recorded"])
        self.assertEqual(report["producers"], ["unrecorded"] * 3)

    def test_attachment_rename_does_not_lose_semantics(self) -> None:
        """Ignore regenerated attachment names when original bytes are identical."""
        source = self.package("original", filename="Photo.png")
        target = self.package("renamed", filename="Other.png")
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["inline_positions_preserved"])
        self.assertTrue(report["attachments_preserved"])
        self.assertFalse(report["raw_rtf_bytes_equal"])

    def test_changed_attachment_bytes_are_detected(self) -> None:
        """Reject replacement image content even when the filename is unchanged."""
        source = self.package("source")
        target = self.package("target", pixel=PIXEL + b"padding")
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertFalse(report["attachments_preserved"])
        self.assertTrue(report["text_preserved"])
        self.assertTrue(report["lost_attachments"])

    def test_changed_paragraph_indent_is_detected(self) -> None:
        """Report paragraph-style loss rather than silently passing RTF changes."""
        source = self.package("source", indent=720)
        target = self.package("target", indent=1440)
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertTrue(report["text_preserved"])
        self.assertFalse(report["styles_preserved"])
        self.assertIn("para-li_720", [item[2] for item in report["lost_styles"]])

    def test_inline_width_change_is_detected(self) -> None:
        """Preserve image resize metadata through TextEdit RTFD exchange."""
        source = self.package("source", width=2400)
        target = self.package("target", width=4800)
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertFalse(report["inline_positions_preserved"])
        self.assertTrue(report["attachments_preserved"])

    def test_record_is_non_overwriting_and_detects_changes(self) -> None:
        """Reject stale checksum manifests after either document or asset edits."""
        source = self.package("source")
        target = self.package("target")
        record = self.root / "source.record.json"
        result = self.run_tool("record", source, "--output", record,
                               "--producer", "constructed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["producer"], "constructed")
        self.assertNotEqual(self.run_tool("record", source, "--output", record,
                                          "--producer", "constructed").returncode, 0)
        self.assertEqual(self.run_tool("compare", source, target,
                                       "--source-record", record).returncode, 0)
        (source / "Photo.png").write_bytes(PIXEL + b"changed")
        result = self.run_tool("compare", source, target, "--source-record", record)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from its recorded bytes", result.stderr)

    def test_macos_textedit_provenance_cannot_be_faked_here(self) -> None:
        """Do not label a Linux-generated file as a genuine TextEdit fixture."""
        source = self.package("fake")
        result = self.run_tool("record", source, "--output", self.root / "fake.json",
                               "--producer", "textedit", "--confirm-textedit-save")
        if sys.platform != "darwin":
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("requires macOS", result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_expected_properties_are_supported(self) -> None:
        """Preserve the preexisting v0.9.12 positional inspector interface."""
        source = self.package("simple", no_image=True)
        expected = self.root / "expected.json"
        expected.write_text(json.dumps({
            "text": "Hello\n", "inline_images": 0,
            "required_styles": ["para-li_720"],
        }), encoding="utf-8")
        result = self.run_tool(source, "--expected", expected)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("para-li_720", result.stdout)

    def test_symlinked_attachment_is_rejected(self) -> None:
        """An RTFD directory cannot escape its verified sibling file set."""
        source = self.package("evil")
        photo = source / "Photo.png"
        photo.unlink()
        photo.symlink_to(self.root / "outside.png")
        self.assertNotEqual(self.run_tool("inspect", source).returncode, 0)

    def test_missing_inline_asset_is_rejected(self) -> None:
        """Never fabricate an inline image identity for a missing file."""
        source = self.package("missing")
        (source / "Photo.png").unlink()
        result = self.run_tool("compare", source, source)
        self.assertNotEqual(result.returncode, 0)

    def test_evidence_is_not_written_inside_the_source_package(self) -> None:
        """Leave every source .rtfd package strictly read-only."""
        source = self.package("original")
        output = source / "evidence.json"
        result = self.run_tool("record", source, "--producer", "constructed",
                               "--output", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_sidecar_mutation_invalidates_the_byte_record(self) -> None:
        """Bind provenance to Finder and native metadata bytes, not just note text."""
        source = self.package("original")
        target = self.package("target")
        evidence = self.root / "source.json"
        self.assertEqual(self.run_tool("record", source, "--producer", "constructed",
                                       "--output", evidence).returncode, 0)
        (source / "._Photo.png").write_bytes(b"changed Finder metadata")
        result = self.run_tool("compare", source, target,
                               "--source-record", evidence)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from its recorded bytes", result.stderr)

    def test_provenance_record_cannot_be_reused_for_another_fixture(self) -> None:
        """A record is bound to its filename as well as source bytes."""
        source = self.package("original")
        target = self.package("other")
        record = self.root / "original.json"
        self.assertEqual(self.run_tool("record", source, "--producer", "constructed",
                                       "--output", record).returncode, 0)
        result = self.run_tool("compare", target, source,
                               "--source-record", record)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another fixture", result.stderr)

    def test_sidecar_does_not_affect_attachment_comparison(self) -> None:
        """Finder metadata is not treated as a user-visible document asset."""
        source = self.package("original")
        target = self.package("resaved")
        (target / "._Photo.png").write_bytes(b"AppleDouble")
        result = self.run_tool("compare", source, target)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
