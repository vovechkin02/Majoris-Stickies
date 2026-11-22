"""Exercise bounded PDF text extraction and independent image rendering."""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "stickies_pdf_text", ROOT / "tools/stickies_pdf_text.py"
)
assert SPEC is not None and SPEC.loader is not None
PDF_TEXT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PDF_TEXT)


def minimal_pdf() -> bytes:
    """Make a minimal valid PDF containing selectable text without fixtures."""
    contents = b"BT /F1 18 Tf 20 40 Td (Hello from Stickies) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] "
         b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length %d >>\nstream\n" % len(contents) + contents + b"\nendstream",
    ]
    document = b"%PDF-1.4\n"
    offsets: list[int] = []
    for number, item in enumerate(objects, 1):
        offsets.append(len(document))
        document += b"%d 0 obj\n" % number + item + b"\nendobj\n"
    cross_reference = len(document)
    document += b"xref\n0 6\n0000000000 65535 f \n"
    for offset in offsets:
        document += b"%010d 00000 n \n" % offset
    return (
        document + b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
        % cross_reference
    )


class PdfTextTests(unittest.TestCase):
    """Confirm text extraction stays bounded and does not modify the PDF."""

    def test_extracts_selectable_text(self) -> None:
        """Extract real text with Poppler rather than OCR or a new image decoder."""
        if shutil.which("pdftotext") is None:
            self.skipTest("Poppler not installed")
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "input.pdf"
            original = minimal_pdf()
            pdf.write_bytes(original)
            self.assertIn("Hello from Stickies", PDF_TEXT.extract_page(pdf))
            self.assertEqual(pdf.read_bytes(), original)

    def test_rejects_symlinks(self) -> None:
        """No output is produced for symlinked paths."""
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "input.pdf"
            pdf.write_bytes(minimal_pdf())
            link = Path(directory) / "linked.pdf"
            link.symlink_to(pdf)
            with self.assertRaises(PDF_TEXT.PdfTextError):
                PDF_TEXT.extract_page(link)

    def test_rejects_non_pdf(self) -> None:
        """A misleading extension cannot bypass document-signature validation."""
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "invalid.pdf"
            pdf.write_bytes(b"not a PDF")
            with self.assertRaises(PDF_TEXT.PdfTextError):
                PDF_TEXT.extract_page(pdf)

    def test_rejects_pages_outside_limit(self) -> None:
        """Reject unbounded page selectors before spawning a subprocess."""
        with self.assertRaises(PDF_TEXT.PdfTextError):
            PDF_TEXT.extract_page(Path("/not/needed"), 0)
        with self.assertRaises(PDF_TEXT.PdfTextError):
            PDF_TEXT.extract_page(Path("/not/needed"), 251)

    def test_rejects_oversized_files(self) -> None:
        """Reject a sparse file without reading its full contents."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "huge.pdf"
            with source.open("wb") as output:
                output.write(b"%PDF-1.4\n")
                output.truncate(PDF_TEXT.MAX_PDF_BYTES + 1)
            with self.assertRaises(PDF_TEXT.PdfTextError):
                PDF_TEXT.extract_page(source)

    def test_cli_stdout_is_plain_text(self) -> None:
        """The installed-command entry point has no metadata or binary output."""
        if shutil.which("pdftotext") is None:
            self.skipTest("Poppler not installed")
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "input.pdf"
            pdf.write_bytes(minimal_pdf())
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools/stickies_pdf_text.py"), str(pdf)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=15,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            self.assertIn(b"Hello from Stickies", completed.stdout)


if __name__ == "__main__":
    unittest.main()
