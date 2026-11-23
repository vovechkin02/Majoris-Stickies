"""Validate exact raster viewport cropping, formats, and portable CLI layout."""

from __future__ import annotations

from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import stickies_image_crop as crop

SVG = "http://www.w3.org/2000/svg"


def valid_png(width: int, height: int) -> bytes:
    """Create a small legitimate RGB PNG using only the standard library."""
    def chunk(name: bytes, data: bytes) -> bytes:
        """Pack one PNG chunk with a computed CRC."""
        return (struct.pack(">I", len(data)) + name + data +
                struct.pack(">I", zlib.crc32(name + data)))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    scanline = b"\x00" + b"\xff\x00\x00" * width
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(scanline * height)) +
            chunk(b"IEND", b""))


class ImageCropTests(unittest.TestCase):
    """Test non-destructive, ratio-correct cropped SVGs and invalid input."""

    def setUp(self) -> None:
        """Allocate a private rectangular raster and new output path."""
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.source = self.root / "sample.png"
        self.source.write_bytes(valid_png(100, 60))
        self.output = self.root / "crop.svg"

    def test_crops_native_pixel_viewport_without_distortion(self) -> None:
        """Verify crop pixels follow source aspect ratio, not the 640x360 UI."""
        before = self.source.read_bytes()
        crop.crop_image(self.source, "image/png", self.output, 10, 20, 50, 50)
        self.assertEqual(self.source.read_bytes(), before)
        tree = ET.parse(self.output)
        root = tree.getroot()
        self.assertEqual(root.get("viewBox"), "10 12 50 30")
        self.assertEqual(root.get("width"), "50")
        self.assertEqual(root.get("height"), "30")
        self.assertEqual(len(root), 1)
        image = root[0]
        self.assertEqual(image.tag, f"{{{SVG}}}image")
        self.assertEqual(image.get("width"), "100")
        self.assertEqual(image.get("height"), "60")
        self.assertTrue(image.get("href", "").startswith("data:image/png;base64,"))
        self.assertNotIn(b"<script", self.output.read_bytes())

    def test_all_supported_raster_headers(self) -> None:
        """Check PNG, GIF, WebP and JPEG metadata without decoding pixels."""
        examples = {
            "image/png": (valid_png(100, 60), (100, 60)),
            "image/gif": (b"GIF89a" + struct.pack("<HH", 320, 240), (320, 240)),
            "image/webp": (b"RIFF" + b"\x10\x00\x00\x00" + b"WEBP" + b"VP8X" +
                           b"\x0a\x00\x00\x00" + b"\x00\x00\x00\x00" +
                           b"\x63\x00\x00" + b"\x3b\x00\x00", (100, 60)),
            "image/jpeg": (b"\xff\xd8\xff\xc0\x00\x11\x08\x00\x3c\x00\x64" +
                           b"\x03" + b"\x00" * 9, (100, 60)),
        }
        for mime, (data, expected) in examples.items():
            with self.subTest(mime=mime):
                self.assertEqual(crop.raster_dimensions(data, mime), expected)

    def test_rejects_outside_or_empty_rectangles(self) -> None:
        """Disallow wraparound rectangles and empty sub-pixel results."""
        for coords in ((90, 10, 20, 40), (0, 90, 50, 20),
                       (-1, 0, 50, 50), (0, 0, 0, 50)):
            with self.subTest(rectangle=coords):
                with self.assertRaises(crop.ImageCropError):
                    crop.crop_image(self.source, "image/png", self.output, *coords)
                self.assertFalse(self.output.exists())

    def test_rejects_source_symlinks_and_existing_output(self) -> None:
        """Avoid following source links or clobbering an existing attachment."""
        linked = self.root / "linked.png"
        linked.symlink_to(self.source)
        with self.assertRaises(crop.ImageCropError):
            crop.crop_image(linked, "image/png", self.output, 5, 5, 90, 90)
        self.assertFalse(self.output.exists())
        self.output.write_text("keep this", encoding="utf-8")
        with self.assertRaises(crop.ImageCropError):
            crop.crop_image(self.source, "image/png", self.output, 5, 5, 90, 90)
        self.assertEqual(self.output.read_text(), "keep this")

    def test_extensionless_installed_command_and_output_privacy(self) -> None:
        """Exercise the actual Debian-installed executable layout and permissions."""
        with tempfile.TemporaryDirectory() as location:
            destination = Path(location)
            for src, name in (("stickies_image_crop.py", "majoris-stickies-image-crop"),
                              ("stickies_image_markup.py", "majoris-stickies-image-markup")):
                shutil.copyfile(TOOLS / src, destination / name)
            result = subprocess.run(
                [sys.executable, str(destination / "majoris-stickies-image-crop"),
                 "--mime", "image/png", "--image", str(self.source),
                 "--output", str(self.output), "--left", "10", "--top", "10",
                 "--width", "80", "--height", "80"],
                capture_output=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.output.stat().st_mode & 0o077, 0)


if __name__ == "__main__":
    unittest.main()
