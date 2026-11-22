#!/usr/bin/env python3
"""Rasterize only the first PDF page for optional Majoris Image display.

This helper never decodes or displays general image files. It executes Poppler
without a shell and returns a private, bounded PNG for ImageKit to display.
The calling GTK note window owns deletion of the returned temporary file.
"""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_PDF_BYTES = 50 * 1024 * 1024
MAX_PNG_BYTES = 6 * 1024 * 1024
MAX_RENDER_SECONDS = 12
MAX_PREVIEW_EDGE = 640


class PdfPreviewError(Exception):
    """Describe rejected inputs or a failed bounded Poppler invocation."""


def render_first_page(source: Path) -> Path:
    """Return a fresh PNG in a 0700 directory, cleaning up on any failure."""
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(source, flags)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_PDF_BYTES:
                raise PdfPreviewError("Only managed PDFs up to 50 MiB can be previewed")
            if os.read(descriptor, 8).lstrip()[:5] != b"%PDF-":
                raise PdfPreviewError("The attachment is not a PDF document")
        finally:
            os.close(descriptor)
    except OSError as error:
        raise PdfPreviewError("Cannot open PDF attachment") from error

    directory = Path(tempfile.mkdtemp(prefix="majoris-stickies-pdf-"))
    prefix = directory / "page"
    output = directory / "page.png"
    success = False
    try:
        command = [
            "pdftoppm", "-f", "1", "-l", "1", "-singlefile", "-png",
            "-scale-to", str(MAX_PREVIEW_EDGE), str(source), str(prefix),
        ]
        completed = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=MAX_RENDER_SECONDS,
            check=False,
        )
        if completed.returncode != 0:
            raise PdfPreviewError("Poppler could not render the first PDF page")
        if not _is_valid_output(output):
            raise PdfPreviewError("The PDF renderer did not produce a safe bounded PNG")
        success = True
        return output
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise PdfPreviewError(
            "Poppler PDF preview is unavailable or timed out"
        ) from error
    finally:
        if not success:
            shutil.rmtree(directory, ignore_errors=True)


def _is_valid_output(path: Path) -> bool:
    """Keep only an ordinary, nonempty PNG within the fixed preview limit."""
    try:
        if path.is_symlink() or not path.is_file():
            return False
        if not 0 < path.stat().st_size <= MAX_PNG_BYTES:
            return False
        with path.open("rb") as stream:
            return stream.read(8) == b"\x89PNG\r\n\x1a\n"
    except OSError:
        return False


def main(argv: list[str] | None = None) -> int:
    """Print one safe temporary output path; errors never expose PDF contents."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args(argv)
    try:
        output = render_first_page(args.source)
        print(output)
    except (PdfPreviewError, OSError) as error:
        print(f"PDF preview failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
