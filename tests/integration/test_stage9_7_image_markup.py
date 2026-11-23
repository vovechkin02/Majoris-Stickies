"""Validate native-ink markup compositing without introducing an image decoder."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "stickies_image_markup", ROOT / "tools/stickies_image_markup.py"
)
assert SPEC and SPEC.loader
markup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(markup)
SVG = "http://www.w3.org/2000/svg"


def native_ink() -> bytes:
    """Produce one valid sketch using the literal InkCanvas SVG vocabulary."""
    return (
        b'<svg xmlns="http://www.w3.org/2000/svg" '
        b'viewBox="0 0 640 360" width="640" height="360">\n'
        b'<path fill="none" stroke="#242424" stroke-width="3" '
        b'stroke-linecap="round" stroke-linejoin="round" '
        b'd="M 12 20 L 17 25"/>\n'
        b'<circle cx="44" cy="77" r="1.5" fill="#242424"/>\n'
        b'</svg>\n'
    )


class ImageMarkupTests(unittest.TestCase):
    """Exercise successful private exports and all trust-boundary rejections."""

    def setUp(self) -> None:
        """Create a unique local raster file with a recognized PNG signature."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.image = self.root / "image.asset"
        # The helper does not decode, so only the signature is necessary here.
        self.image.write_bytes(b"\x89PNG\r\n\x1a\n" + b"test raster")
        self.output = self.root / "annotated.svg"

    def test_markup_round_trip_preserves_original(self) -> None:
        """Embed inert raster data and ink paths without modifying the input."""
        before = self.image.read_bytes()
        markup.write_markup(self.image, "image/png", self.output, native_ink())
        self.assertEqual(self.image.read_bytes(), before)
        tree = ET.parse(self.output)
        root = tree.getroot()
        self.assertEqual(root.tag, f"{{{SVG}}}svg")
        self.assertEqual(len(root), 3)
        self.assertTrue(root[0].get("href", "").startswith("data:image/png;base64,"))
        self.assertEqual(root[1].get("d"), "M 12 20 L 17 25")
        self.assertEqual(root[2].get("cx"), "44")
        self.assertFalse(b"<script" in self.output.read_bytes())

    def test_supported_raster_signatures(self) -> None:
        """Accept exact PNG, JPEG, GIF and WebP signatures without decoding."""
        signatures = {
            "image/png": b"\x89PNG\r\n\x1a\n" + b"raster",
            "image/jpeg": b"\xff\xd8\xff" + b"raster",
            "image/gif": b"GIF89a" + b"raster",
            "image/webp": b"RIFF" + b"abcdWEBP" + b"raster",
        }
        for mime, data in signatures.items():
            with self.subTest(mime=mime):
                self.image.write_bytes(data)
                markup.write_markup(self.image, mime, self.output, native_ink())
                tree = ET.parse(self.output)
                self.assertTrue(
                    tree.getroot()[0].get("href", "").startswith(f"data:{mime};base64,")
                )
                self.assertEqual(self.image.read_bytes(), data)
                self.output.unlink()

    def test_rejects_mime_mismatch_and_active_svg(self) -> None:
        """Only bounded, signature-verified raster bytes may be embedded."""
        for mime in ("image/jpeg", "image/gif", "image/webp", "image/svg+xml"):
            with self.subTest(mime=mime), self.assertRaises(markup.ImageMarkupError):
                markup.write_markup(self.image, mime, self.output, native_ink())
            self.assertFalse(self.output.exists())

    def test_rejects_symlink_and_large_input(self) -> None:
        """Neither symlinks nor oversized files may bypass the source limit."""
        link = self.root / "linked.asset"
        link.symlink_to(self.image)
        with self.assertRaises(markup.ImageMarkupError):
            markup.write_markup(link, "image/png", self.output, native_ink())
        with self.image.open("ab") as stream:
            stream.truncate(markup.MAX_IMAGE_BYTES + 1)
        with self.assertRaises(markup.ImageMarkupError):
            markup.write_markup(self.image, "image/png", self.output, native_ink())

    def test_rejects_script_external_resource_and_complex_svg(self) -> None:
        """Malformed ink never becomes an executable SVG attachment."""
        samples = (
            native_ink().replace(b"</svg>", b'<script>alert(1)</script></svg>'),
            native_ink().replace(b"#242424", b"url(http://malicious.example/)"),
            native_ink().replace(b'M 12 20 L 17 25', b'M 12 20 L 9999 25'),
            native_ink().replace(b'M 12 20 L 17 25', b'M 12 20 L 640 25'),
            native_ink().replace(b"</svg>", b'<image href="file:///etc/passwd"/></svg>'),
            native_ink() + b"<!DOCTYPE svg [ <!ENTITY x SYSTEM 'file:///etc/passwd'> ]>",
            b"A" * (markup.MAX_INK_BYTES + 1),
        )
        for sample in samples:
            with self.subTest(sample=sample[:50]), self.assertRaises(markup.ImageMarkupError):
                markup.write_markup(self.image, "image/png", self.output, sample)
            self.assertFalse(self.output.exists())

    def test_never_overwrites_existing_output(self) -> None:
        """An existing user path is not overwritten after validation."""
        self.output.write_text("keep original", encoding="utf-8")
        with self.assertRaises(markup.ImageMarkupError):
            markup.write_markup(self.image, "image/png", self.output, native_ink())
        self.assertEqual(self.output.read_text(), "keep original")

    def test_cli_accepts_ink_on_stdin(self) -> None:
        """The installed command syntax works without external imaging packages."""
        completed = subprocess.run(
            [sys.executable, str(ROOT / "tools/stickies_image_markup.py"),
             "--mime", "image/png", "--image", str(self.image),
             "--output", str(self.output)],
            input=native_ink(), capture_output=True, timeout=5,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertTrue(self.output.exists())


if __name__ == "__main__":
    unittest.main()
