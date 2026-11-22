"""Verify safe first-page PDF preview conversion and resource limits."""

from __future__ import annotations

import importlib.util
import shutil
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "tools/stickies_pdf_preview.py"
spec = importlib.util.spec_from_file_location("stickies_pdf_preview", MODULE)
assert spec is not None and spec.loader is not None
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


def minimal_pdf() -> bytes:
    """Construct one simple self-contained PDF without external test packages."""
    contents = b"BT /F1 18 Tf 20 40 Td (Hello) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] "
         b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length %d >>\nstream\n" % len(contents) + contents + b"\nendstream",
    ]
    data = b"%PDF-1.4\n"
    offsets: list[int] = []
    for index, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += b"%d 0 obj\n" % index + obj + b"\nendobj\n"
    xref_offset = len(data)
    data += b"xref\n0 6\n0000000000 65535 f \n"
    for offset in offsets:
        data += b"%010d 00000 n \n" % offset
    return (
        data + b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
        % xref_offset
    )


class PdfPreviewTests(unittest.TestCase):
    """Exercise bounded conversion, signature validation, and cleanup."""

    def test_render_first_page_to_bounded_png(self) -> None:
        """Verify real Poppler output when its optional runtime exists."""
        if shutil.which("pdftoppm") is None:
            self.skipTest("poppler-utils not installed")
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "note.pdf"
            source.write_bytes(minimal_pdf())
            result = preview.render_first_page(source)
            try:
                data = result.read_bytes()
                self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
                width, height = struct.unpack(">II", data[16:24])
                self.assertLessEqual(max(width, height), preview.MAX_PREVIEW_EDGE)
                self.assertLessEqual(len(data), preview.MAX_PNG_BYTES)
            finally:
                result.unlink(missing_ok=True)
                result.parent.rmdir()

    def test_rejects_invalid_pdf(self) -> None:
        """Do not invoke Poppler for ordinary or mislabeled attachment files."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "not-pdf.asset"
            source.write_bytes(b"this is not PDF content")
            with self.assertRaises(preview.PdfPreviewError):
                preview.render_first_page(source)

    def test_rejects_symlinks(self) -> None:
        """Do not follow a link to an unintended document."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.pdf"
            source.write_bytes(minimal_pdf())
            link = Path(directory) / "link.pdf"
            link.symlink_to(source)
            with self.assertRaises(preview.PdfPreviewError):
                preview.render_first_page(link)

    def test_rejects_oversized_pdf_before_renderer(self) -> None:
        """Bound input without reading entire potentially sparse files."""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "too-large.pdf"
            with source.open("wb") as stream:
                stream.write(b"%PDF-1.4")
                stream.truncate(preview.MAX_PDF_BYTES + 1)
            with self.assertRaises(preview.PdfPreviewError):
                preview.render_first_page(source)

    def test_rejects_invalid_png_output(self) -> None:
        """Never mistake a non-image result for a preview texture."""
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / "page.png"
            result.write_bytes(b"not png")
            self.assertFalse(preview._is_valid_output(result))


if __name__ == "__main__":
    unittest.main()
