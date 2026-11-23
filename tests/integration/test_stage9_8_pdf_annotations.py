"""Qualify true PDF Ink annotation output and the installed worker interface."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import stickies_pdf_annotate as annotate

try:
    from pypdf import PdfReader, PdfWriter
except ImportError:
    PdfReader = PdfWriter = None


INK = (
    b'<svg xmlns="http://www.w3.org/2000/svg" '
    b'viewBox="0 0 640 360" width="640" height="360">'
    b'<path fill="none" stroke="#242424" stroke-width="3" '
    b'stroke-linecap="round" stroke-linejoin="round" '
    b'd="M 120 60 L 200 140"/>'
    b'<circle cx="280" cy="160" r="1.5" fill="#242424"/>'
    b'</svg>'
)


@unittest.skipIf(PdfWriter is None, "python3-pypdf is an optional dependency")
class PdfInkAnnotationTests(unittest.TestCase):
    """Check actual output dictionary, original bytes, and rejection paths."""

    def setUp(self) -> None:
        """Create a disposable two-page source document."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.original = self.directory / "original.pdf"
        self.output = self.directory / "annotated.pdf"
        pdf = PdfWriter()
        pdf.add_blank_page(width=300, height=150)
        pdf.add_blank_page(width=300, height=150)
        pdf.write(self.original)
        self.original_bytes = self.original.read_bytes()

    def test_creates_standard_ink_annotation_on_correct_page(self) -> None:
        """Verify the PDF's /InkList, output page index, and coordinate mapping."""
        annotate.annotate_pdf(self.original, self.output, 2, INK)
        self.assertEqual(self.original.read_bytes(), self.original_bytes)
        document = PdfReader(self.output)
        self.assertEqual(len(document.pages), 2)
        self.assertNotIn("/Annots", document.pages[0])
        annotations = document.pages[1]["/Annots"]
        self.assertEqual(len(annotations), 1)
        ink = annotations[0].get_object()
        self.assertEqual(ink["/Subtype"], "/Ink")
        self.assertEqual(len(ink["/InkList"]), 2)
        self.assertEqual(len(ink["/InkList"][0]), 4)
        self.assertEqual(len(ink["/InkList"][1]), 4)
        self.assertAlmostEqual(float(ink["/InkList"][0][0]), 56.25, places=2)
        self.assertAlmostEqual(float(ink["/InkList"][0][1]), 131.25, places=2)
        self.assertEqual(self.output.stat().st_mode & 0o077, 0)

    def test_poppler_renders_real_ink_annotations(self) -> None:
        """Check the marked PDF is visibly different in Poppler when available."""
        if not shutil.which("pdftoppm"):
            self.skipTest("Poppler not installed")
        annotate.annotate_pdf(self.original, self.output, 1, INK)
        outputs: list[bytes] = []
        for name, source in (("before", self.original), ("after", self.output)):
            prefix = self.directory / name
            result = subprocess.run(
                ["pdftoppm", "-f", "1", "-l", "1", "-singlefile",
                 "-png", "-scale-to", "640", str(source), str(prefix)],
                check=False, timeout=10, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs.append(prefix.with_suffix(".png").read_bytes())
        self.assertNotEqual(outputs[0], outputs[1])

    def test_rejects_out_of_page_ink_and_rotated_pages(self) -> None:
        """Avoid transposing coordinates for rotated or letterboxed pages."""
        narrow = PdfWriter()
        narrow.add_blank_page(width=60, height=600)
        narrow.write(self.original)
        with self.assertRaisesRegex(annotate.PdfAnnotationError, "outside"):
            annotate.annotate_pdf(self.original, self.output, 1, INK)
        self.assertFalse(self.output.exists())
        rotated = PdfWriter()
        rotated.add_blank_page(width=300, height=150).rotate(90)
        rotated.write(self.original)
        with self.assertRaisesRegex(annotate.PdfAnnotationError, "Rotated"):
            annotate.annotate_pdf(self.original, self.output, 1, INK)

    def test_rejects_invalid_pdf_and_symlinks(self) -> None:
        """Source path spoofing and malformed PDF input must not create output."""
        link = self.directory / "link.pdf"
        link.symlink_to(self.original)
        with self.assertRaises(annotate.PdfAnnotationError):
            annotate.annotate_pdf(link, self.output, 1, INK)
        self.assertFalse(self.output.exists())
        self.original.write_bytes(b"%PDF-NOT A PDF")
        with self.assertRaises(annotate.PdfAnnotationError):
            annotate.annotate_pdf(self.original, self.output, 1, INK)
        self.assertFalse(self.output.exists())

    def test_rejects_pdf_replacement_and_bad_markup(self) -> None:
        """Never overwrite a file or accept active SVG instructions."""
        self.output.write_bytes(b"preserve these bytes")
        with self.assertRaises(annotate.PdfAnnotationError):
            annotate.annotate_pdf(self.original, self.output, 1, INK)
        self.assertEqual(self.output.read_bytes(), b"preserve these bytes")
        self.output.unlink()
        bad = INK.replace(b"</svg>", b"<script>bad</script></svg>")
        with self.assertRaises(annotate.PdfAnnotationError):
            annotate.annotate_pdf(self.original, self.output, 1, bad)
        self.assertFalse(self.output.exists())

    def test_command_line_works_in_source_and_installed_layout(self) -> None:
        """The extensionless Meson-installed helper can locate its validator."""
        with tempfile.TemporaryDirectory() as installed:
            bin_path = Path(installed)
            for source, target in (
                ("stickies_pdf_annotate.py", "majoris-stickies-pdf-annotate"),
                ("stickies_image_markup.py", "majoris-stickies-image-markup"),
            ):
                shutil.copyfile(TOOLS / source, bin_path / target)
            result = subprocess.run(
                [sys.executable, str(bin_path / "majoris-stickies-pdf-annotate"),
                 "--page", "1", "--pdf", str(self.original),
                 "--output", str(self.output)],
                input=INK, capture_output=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(PdfReader(self.output).pages[0]["/Annots"][0].get_object()["/Subtype"], "/Ink")


if __name__ == "__main__":
    unittest.main()
