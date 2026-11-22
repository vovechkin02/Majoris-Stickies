#!/usr/bin/env python3
"""Rasterize one bounded PDF page for optional Majoris Image display.

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
import time
from pathlib import Path

MAX_PDF_BYTES = 50 * 1024 * 1024
MAX_PNG_BYTES = 6 * 1024 * 1024
MAX_RENDER_SECONDS = 12
MAX_PREVIEW_EDGE = 640
MAX_PREVIEW_PAGE = 250
STALE_PREVIEW_SECONDS = 24 * 60 * 60
MAX_CLEANUP_CANDIDATES = 64


class PdfPreviewError(Exception):
    """Describe rejected inputs or a failed bounded Poppler invocation."""


def render_page(source: Path, page: int = 1) -> Path:
    """Return a fresh PNG in a 0700 directory, cleaning up on any failure."""
    if not 1 <= page <= MAX_PREVIEW_PAGE:
        raise PdfPreviewError("PDF page must be between 1 and 250")
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
            "pdftoppm", "-f", str(page), "-l", str(page), "-singlefile", "-png",
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
            raise PdfPreviewError("Poppler could not render the requested PDF page")
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


def render_first_page(source: Path) -> Path:
    """Keep the Stage 8 first-page API for callers and existing tests."""
    return render_page(source, 1)

def cleanup_stale_previews(
    directory: Path | None = None,
    now: float | None = None,
) -> int:
    """Remove bounded, old, privately owned preview outputs left by crashes.

    Only delete a private directory containing exactly one regular page.png.
    Avoid symlink traversal and never recursively delete unrecognized content.
    Preview directories used by active renderers are protected by the age limit.
    """
    root = directory if directory is not None else Path(tempfile.gettempdir())
    cutoff = (time.time() if now is None else now) - STALE_PREVIEW_SECONDS
    removed = 0
    examined = 0
    try:
        candidates = root.glob("majoris-stickies-pdf-*")
        for candidate in candidates:
            examined += 1
            if examined > MAX_CLEANUP_CANDIDATES:
                break
            try:
                info = candidate.lstat()
                if (
                    not stat.S_ISDIR(info.st_mode)
                    or info.st_uid != os.getuid()
                    or info.st_mode & 0o077
                    or info.st_mtime > cutoff
                ):
                    continue
                children = list(candidate.iterdir())
                if len(children) != 1 or children[0].name != "page.png":
                    continue
                preview = children[0]
                image_info = preview.lstat()
                if (
                    not stat.S_ISREG(image_info.st_mode)
                    or image_info.st_uid != os.getuid()
                    or image_info.st_size > MAX_PNG_BYTES
                    or image_info.st_mtime > cutoff
                ):
                    continue
                preview.unlink()
                candidate.rmdir()
                removed += 1
            except OSError:
                # Concurrent cleanup or an unfamiliar directory must not
                # prevent users from previewing their documents.
                continue
    except OSError:
        return removed
    return removed




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
    parser.add_argument("--page", type=int, default=1)
    parser.add_argument("source", type=Path)
    args = parser.parse_args(argv)
    cleanup_stale_previews()
    try:
        output = render_page(args.source, args.page)
        print(output)
    except (PdfPreviewError, OSError) as error:
        print(f"PDF preview failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
