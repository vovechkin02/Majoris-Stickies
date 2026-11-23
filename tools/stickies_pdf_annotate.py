#!/usr/bin/env python3
"""Attach genuine bounded PDF Ink annotations without modifying the original.

Input strokes use the same narrow SVG vocabulary as the native GTK ink canvas.
The selected page is mapped from its 640x360 preview to a PDF crop box; rotated
or password-protected PDFs are rejected rather than producing misplaced ink.
The resulting PDF is a new, private attachment, never an in-place update.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import stat
import sys

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader


def _load_markup_validator():
    """Load the same bounded validator from source or its installed executable."""
    local = Path(__file__).resolve().with_name("stickies_image_markup.py")
    installed = Path(__file__).resolve().with_name("majoris-stickies-image-markup")
    module_path = local if local.is_file() else installed
    loader = SourceFileLoader("_stickies_markup_validator", str(module_path))
    spec = spec_from_loader(loader.name, loader)
    assert spec is not None
    module = module_from_spec(spec)
    loader.exec_module(module)
    return module


_markup = _load_markup_validator()
ImageMarkupError = _markup.ImageMarkupError
MAX_INK_BYTES = _markup.MAX_INK_BYTES
parse_ink = _markup.parse_ink

MAX_PDF_BYTES = 50 * 1024 * 1024
MAX_RESULT_BYTES = 60 * 1024 * 1024
MAX_PAGES = 250
CANVAS_WIDTH = 640
CANVAS_HEIGHT = 360


class PdfAnnotationError(ValueError):
    """Explain an invalid PDF, off-page stroke, or unsafe output destination."""


def _map_strokes(page, ink: bytes):
    """Convert 640x360 native ink into page-relative PDF coordinate arrays."""
    from pypdf.generic import ArrayObject, FloatObject

    box = page.cropbox
    left, bottom = float(box.left), float(box.bottom)
    width, height = float(box.width), float(box.height)
    if not 1 <= width <= 20000 or not 1 <= height <= 20000:
        raise PdfAnnotationError("Unsupported PDF page dimensions")
    if int(page.rotation or 0) % 360 != 0:
        raise PdfAnnotationError("Rotated PDF pages require an unrotated copy")
    if float(page.get("/UserUnit", 1)) != 1.0:
        raise PdfAnnotationError("Nonstandard PDF page user units are unsupported")

    scale = min(CANVAS_WIDTH / width, CANVAS_HEIGHT / height)
    offset_x = (CANVAS_WIDTH - width * scale) / 2.0
    offset_y = (CANVAS_HEIGHT - height * scale) / 2.0

    def position(x: int, y: int) -> tuple[float, float]:
        """Map a coordinate inside the letterboxed preview to PDF user space."""
        x_relative = (x - offset_x) / scale
        y_relative = (y - offset_y) / scale
        if not 0 <= x_relative <= width or not 0 <= y_relative <= height:
            raise PdfAnnotationError("Ink lies outside the rendered PDF page")
        return (left + x_relative, bottom + height - y_relative)

    paths = []
    bounds = []
    for stroke in parse_ink(ink):
        if stroke.tag.endswith("}path"):
            values = [int(value) for value in re.findall(r"\d+", stroke.attrib["d"])]
            points = [position(values[i], values[i + 1]) for i in range(0, len(values), 2)]
        else:
            x, y = position(int(stroke.attrib["cx"]), int(stroke.attrib["cy"]))
            points = [(x - 0.1, y), (x + 0.1, y)]
        flat = ArrayObject()
        for x, y in points:
            flat.extend((FloatObject(x), FloatObject(y)))
            bounds.append((x, y))
        paths.append(flat)
    return ArrayObject(paths), bounds, 3.0 / scale


def annotate_pdf(source: Path, destination: Path, page_number: int, ink: bytes) -> None:
    """Write a new PDF with standard /Ink annotations, preserving source bytes."""
    if not 1 <= page_number <= MAX_PAGES or len(ink) > MAX_INK_BYTES:
        raise PdfAnnotationError("PDF page or pen data exceeds limits")
    if destination.suffix.lower() != ".pdf" or destination.parent.is_symlink():
        raise PdfAnnotationError("Choose a new PDF in a real directory")

    try:
        from pypdf import PdfReader, PdfWriter
        from pypdf.generic import (
            ArrayObject, DictionaryObject, FloatObject, NameObject, NumberObject,
        )
    except ImportError as error:
        raise PdfAnnotationError("Install python3-pypdf to annotate PDF files") from error

    flags = os.O_RDONLY | os.O_NOFOLLOW
    try:
        fd = os.open(source, flags)
    except OSError as error:
        raise PdfAnnotationError("Cannot open the selected PDF") from error
    try:
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_PDF_BYTES:
                raise PdfAnnotationError("PDF must be a regular file of at most 50 MiB")
            if stream.read(5) != b"%PDF-":
                raise PdfAnnotationError("The selected attachment is not a PDF")
            stream.seek(0)
            try:
                reader = PdfReader(stream, strict=True)
                if reader.is_encrypted:
                    raise PdfAnnotationError("Protected PDFs cannot be annotated")
                if len(reader.pages) > MAX_PAGES or page_number > len(reader.pages):
                    raise PdfAnnotationError("The PDF page is outside the supported range")
                paths, bounds, stroke_width = _map_strokes(
                    reader.pages[page_number - 1], ink
                )
                padding = max(stroke_width, 1)
                annotation = DictionaryObject({
                    NameObject("/Type"): NameObject("/Annot"),
                    NameObject("/Subtype"): NameObject("/Ink"),
                    NameObject("/Rect"): ArrayObject([
                        FloatObject(min(x for x, _ in bounds) - padding),
                        FloatObject(min(y for _, y in bounds) - padding),
                        FloatObject(max(x for x, _ in bounds) + padding),
                        FloatObject(max(y for _, y in bounds) + padding),
                    ]),
                    NameObject("/InkList"): paths,
                    NameObject("/C"): ArrayObject([
                        FloatObject(0.141), FloatObject(0.141), FloatObject(0.141),
                    ]),
                    NameObject("/BS"): DictionaryObject({
                        NameObject("/W"): FloatObject(stroke_width),
                    }),
                    NameObject("/F"): NumberObject(4),
                })
                writer = PdfWriter()
                writer.append(reader)
                writer.add_annotation(page_number - 1, annotation)
                writer.add_metadata({"/Producer": "Majoris Stickies"})
                output_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                try:
                    output_fd = os.open(destination, output_flags, 0o600)
                except OSError as error:
                    raise PdfAnnotationError("Output PDF must be a new file") from error
                try:
                    with os.fdopen(output_fd, "wb") as result:
                        writer.write(result)
                        if result.tell() > MAX_RESULT_BYTES:
                            raise PdfAnnotationError("Annotated PDF exceeds the output limit")
                        result.flush()
                        os.fsync(result.fileno())
                except BaseException:
                    destination.unlink(missing_ok=True)
                    raise
            except PdfAnnotationError:
                raise
            except ImageMarkupError as error:
                raise PdfAnnotationError("The pen markup is invalid") from error
            except Exception as error:
                # Untrusted PDFs may fail with parser-specific exception types.
                raise PdfAnnotationError("The PDF could not be safely annotated") from error
    except OSError as error:
        raise PdfAnnotationError("Unable to read the original PDF") from error


def main(argv: list[str] | None = None) -> int:
    """Read bounded native ink on stdin and attach it as PDF Ink annotations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page", type=int, required=True)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    ink = sys.stdin.buffer.read(MAX_INK_BYTES + 1)
    try:
        # Defend the standalone subprocess from compressed PDF resource bombs.
        # Direct library callers are expected to enforce their own limits.
        import resource

        memory_bytes = 512 * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (memory_bytes, memory_bytes))
        resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
        resource.setrlimit(
            resource.RLIMIT_FSIZE, (MAX_RESULT_BYTES, MAX_RESULT_BYTES)
        )
        annotate_pdf(args.pdf, args.output, args.page, ink)
    except (PdfAnnotationError, ImageMarkupError, OSError) as error:
        print(f"PDF annotation: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
