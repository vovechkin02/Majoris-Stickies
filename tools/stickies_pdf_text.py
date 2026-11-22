#!/usr/bin/env python3
"""Extract one bounded PDF page as UTF-8 using Poppler, without decoding images.

Only local regular PDF files are accepted. This helper does not interpret or
modify the document, and it never writes note data. Output is capped so it can
be passed to a GTK text clipboard without blocking on an unbounded document.
"""

from __future__ import annotations

import argparse
import os
import resource
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_PDF_BYTES = 50 * 1024 * 1024
MAX_TEXT_BYTES = 1024 * 1024
MAX_PAGE = 250
MAX_SECONDS = 12


class PdfTextError(Exception):
    """Describe a rejected PDF input or bounded Poppler failure."""


def _limit_output_size() -> None:
    """Apply a child-only file-size limit before invoking the extractor."""
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_TEXT_BYTES + 1, MAX_TEXT_BYTES + 1))


def extract_page(source: Path, page: int = 1) -> str:
    """Return text from a single validated page without persistent temp files."""
    if not 1 <= page <= MAX_PAGE:
        raise PdfTextError("PDF page must be between 1 and 250")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(source, flags)
    except OSError as error:
        raise PdfTextError("Unable to open local PDF attachment") from error

    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_PDF_BYTES:
            raise PdfTextError("PDF must be a regular file of at most 50 MiB")
        if os.read(descriptor, 8).lstrip()[:5] != b"%PDF-":
            raise PdfTextError("The attachment is not a PDF document")
        # The inherited descriptor pins the validated file. A path replacement
        # after validation cannot make Poppler open a different document.
        pinned_path = f"/proc/self/fd/{descriptor}"
        with tempfile.TemporaryDirectory(prefix="stickies-pdf-text-") as directory:
            output = Path(directory) / "page.txt"
            arguments = [
                "pdftotext", "-f", str(page), "-l", str(page),
                "-enc", "UTF-8", "-nopgbrk", pinned_path, str(output),
            ]
            try:
                process = subprocess.run(
                    arguments,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=MAX_SECONDS,
                    check=False,
                    pass_fds=(descriptor,),
                    preexec_fn=_limit_output_size,
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                raise PdfTextError("Poppler text extraction is unavailable or timed out") from error
            if process.returncode != 0:
                raise PdfTextError("Poppler could not extract that page")
            try:
                file_info = output.lstat()
                if not stat.S_ISREG(file_info.st_mode) or file_info.st_size > MAX_TEXT_BYTES:
                    raise PdfTextError("Extracted page exceeds the text limit")
                return output.read_bytes().decode("utf-8", errors="strict")
            except (OSError, UnicodeError) as error:
                raise PdfTextError("The extracted PDF text is invalid") from error
    finally:
        os.close(descriptor)


def main(argv: list[str] | None = None) -> int:
    """Write bounded extracted text to standard output for a consenting caller."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page", type=int, default=1)
    parser.add_argument("source", type=Path)
    args = parser.parse_args(argv)
    try:
        sys.stdout.write(extract_page(args.source, args.page))
    except PdfTextError as error:
        print(f"PDF text extraction failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
