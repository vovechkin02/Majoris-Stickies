#!/usr/bin/env python3
"""Attach bounded, inert SVG ink to a verified raster without decoding it.

Ink paths originate in the native Stickies pen canvas. Source pictures are
shown by Majoris Image in GTK; this helper merely embeds the existing bytes in
an SVG markup copy. Originals are never modified and no image decoder is added.
"""

from __future__ import annotations

import argparse
import base64
import os
from pathlib import Path
import re
import stat
import sys
import xml.etree.ElementTree as ET

CANVAS_WIDTH = 640
CANVAS_HEIGHT = 360
MAX_IMAGE_BYTES = 1024 * 1024
MAX_INK_BYTES = 128 * 1024
SVG_NAMESPACE = "http://www.w3.org/2000/svg"
MIME_SIGNATURES = {
    "image/png": (b"\x89PNG\r\n\x1a\n",),
    "image/jpeg": (b"\xff\xd8\xff",),
    "image/gif": (b"GIF87a", b"GIF89a"),
    "image/webp": (b"RIFF",),
}
PATH_COMMANDS = re.compile(r"M [0-9]{1,3} [0-9]{1,3}(?: L [0-9]{1,3} [0-9]{1,3}){1,500}\Z")


class ImageMarkupError(ValueError):
    """Describe a rejected raster, ink stream or output destination."""


def read_raster(path: Path, mime: str) -> bytes:
    """Read one bounded, regular raster while excluding symbolic links."""
    if mime not in MIME_SIGNATURES:
        raise ImageMarkupError("Only PNG, JPEG, GIF and WebP can be marked up")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_IMAGE_BYTES:
                raise ImageMarkupError("Raster must be a regular file under 1 MiB")
            data = stream.read(MAX_IMAGE_BYTES + 1)
    except OSError as error:
        raise ImageMarkupError("Unable to read the selected raster") from error
    if len(data) > MAX_IMAGE_BYTES or not any(
        data.startswith(magic) for magic in MIME_SIGNATURES[mime]
    ):
        raise ImageMarkupError("Raster signature or size does not match its MIME type")
    if mime == "image/webp" and (len(data) < 12 or data[8:12] != b"WEBP"):
        raise ImageMarkupError("Invalid WebP signature")
    return data


def parse_ink(payload: bytes) -> list[ET.Element]:
    """Accept only numeric path/circle strokes emitted by the native pen canvas."""
    if len(payload) > MAX_INK_BYTES or b"<!" in payload:
        raise ImageMarkupError("Ink markup is too large or contains forbidden XML")
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as error:
        raise ImageMarkupError("Invalid pen markup") from error
    if root.tag != f"{{{SVG_NAMESPACE}}}svg" or root.attrib != {
        "viewBox": "0 0 640 360", "width": "640", "height": "360"
    }:
        raise ImageMarkupError("Expected a native 640×360 pen canvas")
    strokes = list(root)
    if not 1 <= len(strokes) <= 128 or (root.text or "").strip():
        raise ImageMarkupError("The ink canvas must contain 1–128 strokes")
    for item in strokes:
        if list(item) or (item.text or "").strip() or (item.tail or "").strip():
            raise ImageMarkupError("Nested or text ink elements are forbidden")
        if item.tag == f"{{{SVG_NAMESPACE}}}path":
            if set(item.attrib) != {
                "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "d"
            } or (item.get("fill"), item.get("stroke"), item.get("stroke-width"),
                  item.get("stroke-linecap"), item.get("stroke-linejoin")) != (
                "none", "#242424", "3", "round", "round"
            ) or not PATH_COMMANDS.fullmatch(item.get("d", "")):
                raise ImageMarkupError("Unsupported pen path")
            coordinates = list(map(int, re.findall(r"[0-9]+", item.get("d", ""))))
            if any(value >= CANVAS_WIDTH for value in coordinates[::2]) or any(
                value >= CANVAS_HEIGHT for value in coordinates[1::2]
            ):
                raise ImageMarkupError("Pen path extends outside the canvas")
        elif item.tag == f"{{{SVG_NAMESPACE}}}circle":
            if set(item.attrib) != {"cx", "cy", "r", "fill"} or (
                item.get("r"), item.get("fill")
            ) != ("1.5", "#242424"):
                raise ImageMarkupError("Unsupported pen point")
            for coordinate, maximum in (("cx", CANVAS_WIDTH), ("cy", CANVAS_HEIGHT)):
                value = item.get(coordinate, "")
                if not value.isascii() or not value.isdecimal() or int(value) >= maximum:
                    raise ImageMarkupError("Pen point is outside the canvas")
        else:
            raise ImageMarkupError("Only native pen strokes may be embedded")
    return strokes


def compose_markup(image_bytes: bytes, mime: str, ink: bytes) -> bytes:
    """Build an inert annotated image copy with no scripts, URLs, or external files."""
    strokes = parse_ink(ink)
    ET.register_namespace("", SVG_NAMESPACE)
    svg = ET.Element(f"{{{SVG_NAMESPACE}}}svg", {
        "viewBox": "0 0 640 360", "width": "640", "height": "360"
    })
    ET.SubElement(svg, f"{{{SVG_NAMESPACE}}}image", {
        "x": "0", "y": "0", "width": "640", "height": "360",
        "preserveAspectRatio": "xMidYMid meet",
        "href": f"data:{mime};base64,{base64.b64encode(image_bytes).decode('ascii')}",
    })
    svg.extend(strokes)
    return ET.tostring(svg, encoding="utf-8", xml_declaration=True) + b"\n"


def write_markup(source: Path, mime: str, destination: Path, ink: bytes) -> None:
    """Write a new private SVG atomically and never replace the user's original."""
    image_bytes = read_raster(source, mime)
    combined = compose_markup(image_bytes, mime, ink)
    if destination.suffix.lower() != ".svg" or destination.parent.is_symlink():
        raise ImageMarkupError("Choose a new SVG output in a real directory")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(destination, flags, 0o600)
    except OSError as error:
        raise ImageMarkupError("The SVG destination must be a new file") from error
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(combined)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    """Read one native SVG sketch from stdin and produce an annotated raster copy."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mime", required=True, choices=sorted(MIME_SIGNATURES))
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    options = parser.parse_args(argv)
    ink = sys.stdin.buffer.read(MAX_INK_BYTES + 1)
    try:
        write_markup(options.image, options.mime, options.output, ink)
    except (ImageMarkupError, OSError) as error:
        print(f"Image markup: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
