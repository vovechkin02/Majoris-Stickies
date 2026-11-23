#!/usr/bin/env python3
"""Attach genuine bounded PDF Ink annotations without modifying the original.

Input strokes use the same narrow SVG vocabulary as the native GTK ink canvas.
The page geometry maps ink from the 640×360 letterboxed preview into the
PDF's crop box, including quarter-turn /Rotate values. Protected/signed PDFs
are rejected to avoid invalid signatures or silently altered permissions.
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


def _geometry(page):
    """Validate a page and return its crop dimensions, rotation and preview fit."""
    box = page.cropbox
    left, bottom = float(box.left), float(box.bottom)
    width, height = float(box.width), float(box.height)
    if not 1 <= width <= 20000 or not 1 <= height <= 20000:
        raise PdfAnnotationError("Unsupported PDF page dimensions")
    rotation = int(page.get("/Rotate", 0) or 0) % 360
    if rotation not in (0, 90, 180, 270):
        raise PdfAnnotationError("Unsupported PDF page rotation")
    if float(page.get("/UserUnit", 1)) != 1.0:
        raise PdfAnnotationError("Nonstandard PDF user units are unsupported")
    visual_width, visual_height = ((height, width) if rotation in (90, 270)
                                   else (width, height))
    scale = min(CANVAS_WIDTH / visual_width, CANVAS_HEIGHT / visual_height)
    offset_x = (CANVAS_WIDTH - visual_width * scale) / 2.0
    offset_y = (CANVAS_HEIGHT - visual_height * scale) / 2.0
    return left, bottom, width, height, rotation, scale, offset_x, offset_y


def _preview_to_pdf(page, x: float, y: float) -> tuple[float, float]:
    """Undo the displayed quarter-turn after removing the preview's letterbox."""
    left, bottom, width, height, rotation, scale, ox, oy = _geometry(page)
    visual_width, visual_height = ((height, width) if rotation in (90, 270)
                                   else (width, height))
    vx = (x - ox) / scale
    vy = (y - oy) / scale
    if not (-0.00001 <= vx <= visual_width + 0.00001 and
            -0.00001 <= vy <= visual_height + 0.00001):
        raise PdfAnnotationError("Ink lies outside the rendered PDF page")
    vx = min(visual_width, max(0.0, vx))
    vy = min(visual_height, max(0.0, vy))
    if rotation == 0:
        px, py = vx, height - vy
    elif rotation == 90:
        px, py = vy, vx
    elif rotation == 180:
        px, py = width - vx, vy
    else:
        px, py = width - vy, height - vx
    return left + px, bottom + py


def _map_strokes(page, ink: bytes):
    """Convert bounded 640×360 native ink into the rotated PDF's coordinate space."""
    from pypdf.generic import ArrayObject, FloatObject

    scale = _geometry(page)[5]
    paths = []
    bounds = []
    for stroke in parse_ink(ink):
        if stroke.tag.endswith("}path"):
            values = [int(value) for value in re.findall(r"\d+", stroke.attrib["d"])]
            points = [_preview_to_pdf(page, values[i], values[i + 1])
                      for i in range(0, len(values), 2)]
        else:
            x, y = _preview_to_pdf(page, int(stroke.attrib["cx"]),
                                   int(stroke.attrib["cy"]))
            points = [(x - 0.1, y), (x + 0.1, y)]
        flat = ArrayObject()
        for x, y in points:
            flat.extend((FloatObject(x), FloatObject(y)))
            bounds.append((x, y))
        paths.append(flat)
    return ArrayObject(paths), bounds, 3.0 / scale


def _ink_references(page) -> list[tuple[int, object]]:
    """Locate only actual Ink annotations while retaining other PDF annotations."""
    refs = page.get("/Annots")
    if refs is None:
        return []
    refs = refs.get_object()
    if len(refs) > 1000:
        raise PdfAnnotationError("Too many page annotations")
    result = []
    for index, ref in enumerate(refs):
        try:
            if ref.get_object().get("/Subtype") == "/Ink":
                result.append((index, ref))
        except (AttributeError, ValueError, KeyError) as error:
            raise PdfAnnotationError("Invalid existing annotation") from error
    return result


def _check_editable(reader, page_number: int) -> None:
    """Refuse protected/signature-bearing documents and invalid page numbers."""
    if reader.is_encrypted:
        raise PdfAnnotationError("Protected PDFs cannot be annotated")
    if len(reader.pages) > MAX_PAGES or not 1 <= page_number <= len(reader.pages):
        raise PdfAnnotationError("The PDF page is outside the supported range")
    root = reader.trailer["/Root"]
    if root.get("/Perms"):
        raise PdfAnnotationError("Signed or permission-protected PDF is read-only")
    acro = root.get("/AcroForm")
    if acro:
        acro = acro.get_object()
        for ref in acro.get("/Fields", [])[:1000]:
            field = ref.get_object()
            if field.get("/FT") == "/Sig":
                raise PdfAnnotationError("Signed PDF must not be rewritten")
    _geometry(reader.pages[page_number - 1])


def ink_count(source: Path, page_number: int) -> int:
    """Return the number of selectable Ink annotations on a validated PDF page."""
    try:
        from pypdf import PdfReader
    except ImportError as error:
        raise PdfAnnotationError("Install python3-pypdf to inspect PDF Ink") from error

    with _open_pdf(source) as stream:
        try:
            reader = PdfReader(stream, strict=True)
            _check_editable(reader, page_number)
            return len(_ink_references(reader.pages[page_number - 1]))
        except PdfAnnotationError:
            raise
        except Exception as error:
            raise PdfAnnotationError("Could not inspect PDF Ink annotations") from error


def _open_pdf(source: Path):
    """Open a pinned, bounded regular PDF without following filesystem symlinks."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(source, flags)
    except OSError as error:
        raise PdfAnnotationError("Cannot open the selected PDF") from error
    stream = os.fdopen(descriptor, "rb")
    info = os.fstat(stream.fileno())
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_PDF_BYTES:
        stream.close()
        raise PdfAnnotationError("PDF must be a regular file of at most 50 MiB")
    if stream.read(5) != b"%PDF-":
        stream.close()
        raise PdfAnnotationError("The selected attachment is not a PDF")
    stream.seek(0)
    return stream


def annotate_pdf(
    source: Path,
    destination: Path,
    page_number: int,
    ink: bytes,
    operation: str = "add",
    ink_index: int | None = None,
) -> None:
    """Save a distinct PDF after adding, replacing or removing one Ink annotation."""
    if not 1 <= page_number <= MAX_PAGES or len(ink) > MAX_INK_BYTES:
        raise PdfAnnotationError("PDF page or pen data exceeds limits")
    if operation not in ("add", "replace", "remove"):
        raise PdfAnnotationError("Unsupported PDF annotation operation")
    if (operation == "add" and ink_index is not None or
            operation != "add" and (ink_index is None or ink_index < 1)):
        raise PdfAnnotationError("Select an existing Ink annotation")
    if operation == "remove" and ink.strip():
        raise PdfAnnotationError("Removing Ink does not accept replacement strokes")
    if operation != "remove" and not ink.strip():
        raise PdfAnnotationError("Ink markup cannot be empty")
    if destination.suffix.lower() != ".pdf" or destination.parent.is_symlink():
        raise PdfAnnotationError("Choose a new PDF in a real directory")

    try:
        from pypdf import PdfReader, PdfWriter
        from pypdf.generic import (
            ArrayObject, DictionaryObject, FloatObject, NameObject, NumberObject,
        )
    except ImportError as error:
        raise PdfAnnotationError("Install python3-pypdf to annotate PDF files") from error

    try:
        with _open_pdf(source) as stream:
            try:
                reader = PdfReader(stream, strict=True)
                _check_editable(reader, page_number)
                page = reader.pages[page_number - 1]
                selected = _ink_references(page)
                if operation != "add" and ink_index > len(selected):
                    raise PdfAnnotationError("Selected Ink annotation no longer exists")
                if operation != "remove":
                    paths, bounds, stroke_width = _map_strokes(page, ink)
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
                target = writer.pages[page_number - 1]
                if operation != "add":
                    existing = _ink_references(target)
                    selected_position = existing[ink_index - 1][0]
                    target["/Annots"].get_object().pop(selected_position)
                if operation != "remove":
                    writer.add_annotation(page_number - 1, annotation)
                writer.add_metadata({"/Producer": "Majoris Stickies"})
                if operation != "add":
                    # Prune the removed Ink object itself, not just its page link.
                    # Otherwise an obsolete annotation remains recoverable as
                    # an unreachable object in the new PDF byte stream.
                    writer.compress_identical_objects (
                        remove_identicals=False, remove_orphans=True
                    )
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
                raise PdfAnnotationError("The PDF could not be safely annotated") from error
    except OSError as error:
        raise PdfAnnotationError("Unable to read the original PDF") from error


def main(argv: list[str] | None = None) -> int:
    """Read bounded native ink on stdin and attach it as PDF Ink annotations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page", type=int, required=True)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--operation", choices=("add", "replace", "remove"), default="add")
    parser.add_argument("--index", type=int)
    parser.add_argument("--list-ink", action="store_true")
    args = parser.parse_args(argv)
    ink = b"" if args.list_ink or args.operation == "remove" else sys.stdin.buffer.read(MAX_INK_BYTES + 1)
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
        if args.list_ink:
            print(ink_count(args.pdf, args.page))
        elif args.output is None:
            raise PdfAnnotationError("A new output path is required")
        else:
            annotate_pdf(args.pdf, args.output, args.page, ink,
                         operation=args.operation, ink_index=args.index)
    except (PdfAnnotationError, ImageMarkupError, OSError) as error:
        print(f"PDF annotation: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
