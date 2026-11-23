"""Rotation-aware PDF Ink placement, editing/removal, signing safety and CLI tests."""

from __future__ import annotations

import subprocess
import shutil
from pathlib import Path
import tempfile
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import stickies_pdf_annotate as pdf
try:
    from pypdf import PdfReader, PdfWriter
except ImportError:
    PdfReader = PdfWriter = None


def ink_path(points: list[tuple[int, int]]) -> bytes:
    """Encode a bounded native input path."""
    command = " L ".join(f"{x} {y}" for x, y in points)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 360" '
        'width="640" height="360"><path fill="none" stroke="#242424" '
        'stroke-width="3" stroke-linecap="round" stroke-linejoin="round" '
        f'd="M {command}"/></svg>'
    ).encode()


@unittest.skipIf(PdfWriter is None, "python3-pypdf is an optional dependency")
class PdfInkEditingTests(unittest.TestCase):
    """Test all quarter rotations and safe, selectable Ink replacement."""

    def setUp(self) -> None:
        """Create a real PDF with two independent pages and distinct attachments."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "original.pdf"
        self.destination = self.root / "copy.pdf"
        doc = PdfWriter()
        doc.add_blank_page(width=300, height=150)
        doc.add_blank_page(width=300, height=150)
        doc.write(self.source)
        self.before = self.source.read_bytes()

    def test_all_rotations_coordinate_inverse(self) -> None:
        """Map corners to the crop box for all four quarter-turn orientations."""
        for angle in (0, 90, 180, 270):
            with self.subTest(angle=angle):
                doc = PdfWriter()
                doc.add_blank_page(width=300, height=150).rotate(angle)
                doc.write(self.source)
                page = PdfReader(self.source).pages[0]
                _, _, w, h, rot, scale, ox, oy = pdf._geometry(page)
                vw, vh = ((h, w) if rot in (90, 270) else (w, h))
                corners = ((ox, oy), (ox + vw * scale, oy),
                           (ox, oy + vh * scale), (ox + vw * scale, oy + vh * scale))
                mapped = [pdf._preview_to_pdf(page, x, y) for x, y in corners]
                self.assertEqual({(round(x), round(y)) for x, y in mapped},
                                 {(0, 0), (0, 150), (300, 0), (300, 150)})
                mid = (round(ox + vw * scale / 2), round(oy + vh * scale / 2))
                input_ink = ink_path([mid, (mid[0] + 2, mid[1] + 2)])
                pdf.annotate_pdf(self.source, self.destination, 1, input_ink)
                self.assertEqual(pdf.ink_count(self.destination, 1), 1)
                annotation = PdfReader(self.destination).pages[0]["/Annots"][0].get_object()
                point = annotation["/InkList"][0]
                self.assertAlmostEqual(float(point[0]), 150, delta=1.1)
                self.assertAlmostEqual(float(point[1]), 75, delta=1.1)
                self.destination.unlink()

    def test_nonzero_cropbox_offsets_and_page_selection(self) -> None:
        """Preserve native coordinates when the crop box doesn't begin at zero."""
        writer = PdfWriter()
        page = writer.add_blank_page(width=450, height=300)
        page.cropbox.lower_left = (30, 50)
        page.cropbox.upper_right = (330, 200)
        writer.write(self.source)
        pdf.annotate_pdf(self.source, self.destination, 1,
                         ink_path([(320, 170), (330, 170)]))
        annotation = PdfReader(self.destination).pages[0]["/Annots"][0].get_object()
        self.assertAlmostEqual(float(annotation["/InkList"][0][0]), 180, delta=0.1)
        expected_y = pdf._preview_to_pdf(PdfReader(self.source).pages[0], 320, 170)[1]
        self.assertAlmostEqual(float(annotation["/InkList"][0][1]), expected_y, delta=0.1)

    def test_replace_and_remove_preserve_unrelated_annotations(self) -> None:
        """Replace only the selected Ink and leave a separate text annotation."""
        a = ink_path([(120, 80), (200, 80)])
        b = ink_path([(120, 120), (200, 120)])
        pdf.annotate_pdf(self.source, self.destination, 1, a)
        doc1 = self.root / "second.pdf"
        pdf.annotate_pdf(self.destination, doc1, 1, b)
        before = PdfReader(doc1)
        self.assertEqual(pdf.ink_count(doc1, 1), 2)
        # Preserve a non-Ink annotation as an unrelated object.
        writer = PdfWriter()
        writer.append(before)
        from pypdf.annotations import Text
        writer.add_annotation(0, Text(rect=(10, 10, 30, 30), text="Keep me"))
        doc2 = self.root / "with-text.pdf"
        writer.write(doc2)
        original_with_text = doc2.read_bytes()
        replaced = self.root / "replaced.pdf"
        pdf.annotate_pdf(doc2, replaced, 1, b, "replace", 1)
        self.assertEqual(pdf.ink_count(replaced, 1), 2)
        kinds = [str(ref.get_object()["/Subtype"])
                 for ref in PdfReader(replaced).pages[0]["/Annots"]]
        self.assertEqual(kinds.count("/Text"), 1)
        removed = self.root / "removed.pdf"
        pdf.annotate_pdf(replaced, removed, 1, b"", "remove", 2)
        self.assertEqual(pdf.ink_count(removed, 1), 1)
        self.assertEqual(len(PdfReader(removed).pages[0]["/Annots"]), 2)
        self.assertEqual(doc2.read_bytes(), original_with_text)
        self.assertEqual(self.source.read_bytes(), self.before)

    def test_removal_scrubs_orphaned_ink_objects(self) -> None:
        """Removing the last Ink must not leave recoverable unused Ink objects."""
        pdf.annotate_pdf(self.source, self.destination, 1,
                         ink_path([(120, 80), (200, 80)]))
        removed = self.root / "scrubbed.pdf"
        pdf.annotate_pdf(self.destination, removed, 1, b"", "remove", 1)
        self.assertNotIn(b"/InkList", removed.read_bytes())
        self.assertEqual(pdf.ink_count(removed, 1), 0)
        self.assertIn(b"/InkList", self.destination.read_bytes())

    def test_rejects_signed_or_protected_pdf(self) -> None:
        """Never silently invalidate an existing signature/permissions catalog."""
        from pypdf.generic import DictionaryObject, NameObject
        protected = PdfWriter()
        protected.add_blank_page(width=300, height=150)
        protected._root_object[NameObject("/Perms")] = DictionaryObject({
            NameObject("/DocMDP"): DictionaryObject(),
        })
        protected.write(self.source)
        with self.assertRaisesRegex(pdf.PdfAnnotationError, "Signed"):
            pdf.annotate_pdf(self.source, self.destination, 1,
                             ink_path([(120, 80), (200, 80)]))
        self.assertFalse(self.destination.exists())

    def test_poppler_coordinates_match_preview_across_rotations(self) -> None:
        """Verify actual annotation position in Poppler at each quarter-turn."""
        if not shutil.which("pdftoppm"):
            self.skipTest("Poppler is unavailable")
        try:
            from PIL import Image, ImageChops
        except ImportError:
            self.skipTest("Pillow visual assertion dependency is unavailable")
        for rotation in (0, 90, 180, 270):
            with self.subTest(rotation=rotation):
                writer = PdfWriter()
                writer.add_blank_page(width=300, height=150).rotate(rotation)
                writer.write(self.source)
                geometry = pdf._geometry(PdfReader(self.source).pages[0])
                _, _, width, height, angle, scale, ox, oy = geometry
                display_width, display_height = (
                    (height, width) if angle in (90, 270) else (width, height)
                )
                start = (round(ox + display_width * scale * .25),
                         round(oy + display_height * scale * .25))
                end = (start[0] + 8, start[1] + 8)
                pdf.annotate_pdf(self.source, self.destination, 1,
                                 ink_path([start, end]))
                prefix = self.root / f"render-{rotation}"
                result = subprocess.run(
                    ["pdftoppm", "-f", "1", "-l", "1", "-singlefile",
                     "-png", "-scale-to", "640", str(self.destination), str(prefix)],
                    capture_output=True, check=False, timeout=12,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                rendered = Image.open(prefix.with_suffix(".png")).convert("RGB")
                delta = ImageChops.difference(
                    rendered, Image.new("RGB", rendered.size, "white")
                )
                bounds = delta.getbbox()
                self.assertIsNotNone(bounds)
                center_x = (bounds[0] + bounds[2]) / (2 * rendered.width)
                center_y = (bounds[1] + bounds[3]) / (2 * rendered.height)
                self.assertAlmostEqual(center_x, .25, delta=.08)
                self.assertAlmostEqual(center_y, .25, delta=.08)
                self.destination.unlink()

    def test_invalid_selection_never_creates_output(self) -> None:
        """Reject nonexistent selection and accidental in-place writes."""
        with self.assertRaisesRegex(pdf.PdfAnnotationError, "no longer exists"):
            pdf.annotate_pdf(self.source, self.destination, 1,
                             ink_path([(120, 80), (200, 80)]), "replace", 1)
        self.assertFalse(self.destination.exists())
        with self.assertRaises(pdf.PdfAnnotationError):
            pdf.annotate_pdf(self.source, self.source, 1, b"", "remove", 1)
        self.assertEqual(self.source.read_bytes(), self.before)

    def test_cli_lists_and_removes_existing_ink(self) -> None:
        """Check the installed command's numeric output and --operation remove."""
        pdf.annotate_pdf(self.source, self.destination, 1,
                         ink_path([(120, 80), (200, 80)]))
        command = ROOT / "tools" / "stickies_pdf_annotate.py"
        check = subprocess.run([sys.executable, str(command), "--list-ink",
                                "--page", "1", "--pdf", str(self.destination)],
                               capture_output=True, timeout=10, check=True)
        self.assertEqual(check.stdout.strip(), b"1")
        removed = self.root / "cli-removed.pdf"
        subprocess.run([sys.executable, str(command), "--page", "1",
                        "--pdf", str(self.destination), "--output", str(removed),
                        "--operation", "remove", "--index", "1"],
                       capture_output=True, timeout=15, check=True)
        self.assertEqual(pdf.ink_count(removed, 1), 0)


if __name__ == "__main__":
    unittest.main()
