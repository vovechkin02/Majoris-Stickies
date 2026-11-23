"""Exercise UI geometry probing, aspect-fit alignment, and rendered SVG crops."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

try:
    from PIL import Image
    import cairosvg
except ImportError:
    Image = cairosvg = None

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import stickies_image_crop as crop
import stickies_image_markup as markup


@unittest.skipIf(Image is None or cairosvg is None,
                 "Pillow and CairoSVG are optional rendering test dependencies")
class CropGeometryQualification(unittest.TestCase):
    """Verify the raster header, preview fit and saved crop independently."""

    def setUp(self) -> None:
        """Create isolated, fully decoded source images with known boundaries."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def _create(self, width: int, height: int) -> Path:
        """Produce a true PNG with color bands indicating source coordinates."""
        picture = Image.new("RGB", (width, height))
        for y in range(height):
            for x in range(width):
                picture.putpixel((x, y), (x * 255 // width, y * 255 // height, 40))
        path = self.root / f"{width}x{height}.png"
        picture.save(path)
        return path

    def test_probe_reports_native_dimensions_for_each_aspect_ratio(self) -> None:
        """Probe portrait, landscape, and square without decoding in GTK."""
        for width, height in ((40, 120), (160, 48), (90, 90)):
            with self.subTest(size=(width, height)):
                src = self._create(width, height)
                result = subprocess.run(
                    [sys.executable, str(ROOT / "tools" / "stickies_image_crop.py"),
                     "--probe", "--image", str(src), "--mime", "image/png"],
                    check=True, capture_output=True, timeout=5,
                )
                self.assertEqual(result.stdout.strip(), f"{width} {height}".encode())
                for edge in ((640, 360), (640, 330), (320, 180), (960, 540)):
                    scale = min(edge[0] / width, edge[1] / height)
                    fitted_width = width * scale
                    fitted_height = height * scale
                    self.assertLessEqual(fitted_width, edge[0])
                    self.assertLessEqual(fitted_height, edge[1])
                    self.assertAlmostEqual(fitted_width / fitted_height,
                                           width / height, places=9)
                    self.assertGreaterEqual((edge[0] - fitted_width) / 2, 0)
                    self.assertGreaterEqual((edge[1] - fitted_height) / 2, 0)

    def test_svg_crop_renders_correct_pixels_independent_of_preview_size(self) -> None:
        """Compare real crop pixels after SVG rendering for multiple aspect ratios."""
        for width, height in ((40, 120), (160, 48), (90, 90)):
            with self.subTest(size=(width, height)):
                src = self._create(width, height)
                data = markup.read_raster(src, "image/png")
                svg = crop.compose_crop(data, "image/png", 25, 25, 50, 50)
                actual = Image.open(BytesIO(cairosvg.svg2png(bytestring=svg))).convert("RGB")
                expected = Image.open(src).crop((round(width * .25), round(height * .25),
                                                  round(width * .75), round(height * .75)))
                self.assertEqual(actual.size, expected.size)
                for point in ((0, 0), (actual.width // 2, actual.height // 2),
                              (actual.width - 1, actual.height - 1)):
                    for a, b in zip(actual.getpixel(point), expected.getpixel(point)):
                        self.assertLessEqual(abs(a - b), 1)

    def test_markup_svg_uses_contain_geometry_and_native_ink_coordinates(self) -> None:
        """Keep letterbox edges aligned between a preview and its saved SVG."""
        for width, height in ((40, 120), (160, 48), (90, 90)):
            src = self._create(width, height)
            scale = min(640 / width, 360 / height)
            offset_x = (640 - width * scale) / 2
            offset_y = (360 - height * scale) / 2
            center_x = round(offset_x + width * scale / 2)
            center_y = round(offset_y + height * scale / 2)
            ink = (
                '<svg xmlns="http://www.w3.org/2000/svg" '
                'viewBox="0 0 640 360" width="640" height="360">'
                f'<circle cx="{center_x}" cy="{center_y}" r="1.5" '
                'fill="#242424"/></svg>'
            ).encode()
            result = markup.compose_markup(src.read_bytes(), "image/png", ink)
            rendered = Image.open(BytesIO(cairosvg.svg2png(bytestring=result))).convert("RGBA")
            self.assertEqual(rendered.size, (640, 360))
            red, green, blue, alpha = rendered.getpixel((center_x, center_y))
            self.assertLess(max(red, green, blue), 50)
            self.assertGreater(alpha, 240)


if __name__ == "__main__":
    unittest.main()
