#!/usr/bin/env python3
"""Create a precise, non-destructive SVG crop of a managed raster.

No raster decoding is performed here: bounded image-header metadata supplies
native pixel dimensions, and the existing image bytes remain embedded inside a
self-contained SVG viewport. Majoris Image remains the UI image renderer.
"""

from __future__ import annotations

import argparse
import base64
import os
from pathlib import Path
import struct
import stat
import sys
import xml.etree.ElementTree as ET

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader


def _load_markup_validator():
    """Share raster verification with the installed native markup helper."""
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
read_raster = _markup.read_raster
SVG_NAMESPACE = _markup.SVG_NAMESPACE

MAX_DIMENSION = 20000
MAX_AREA = 50_000_000


class ImageCropError(ValueError):
    """Reject invalid or unsupported raster metadata and crop rectangles."""


def raster_dimensions(data: bytes, mime: str) -> tuple[int, int]:
    """Read intrinsic image dimensions from headers without decoding pixels."""
    width = height = 0
    if mime == "image/png":
        if len(data) >= 24 and data[12:16] == b"IHDR":
            width, height = struct.unpack(">II", data[16:24])
    elif mime == "image/gif":
        if len(data) >= 10:
            width, height = struct.unpack("<HH", data[6:10])
    elif mime == "image/jpeg":
        index = 2
        markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                   0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        while index + 4 < len(data):
            if data[index] != 0xff:
                break
            index += 1
            while index < len(data) and data[index] == 0xff:
                index += 1
            if index >= len(data):
                break
            marker = data[index]
            index += 1
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
                continue
            if marker == 0xDA or index + 2 > len(data):
                break
            length = int.from_bytes(data[index:index + 2], "big")
            if length < 2 or index + length > len(data):
                break
            if marker in markers and length >= 7:
                height = int.from_bytes(data[index + 3:index + 5], "big")
                width = int.from_bytes(data[index + 5:index + 7], "big")
                break
            index += length
    elif mime == "image/webp" and len(data) >= 30:
        kind = data[12:16]
        if kind == b"VP8X":
            width = int.from_bytes(data[24:27], "little") + 1
            height = int.from_bytes(data[27:30], "little") + 1
        elif kind == b"VP8L" and data[20] == 0x2f:
            width = 1 + data[21] + ((data[22] & 0x3f) << 8)
            height = 1 + (data[22] >> 6) + (data[23] << 2) + ((data[24] & 0xf) << 10)
        elif kind == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            width = int.from_bytes(data[26:28], "little") & 0x3fff
            height = int.from_bytes(data[28:30], "little") & 0x3fff
    if not 1 <= width <= MAX_DIMENSION or not 1 <= height <= MAX_DIMENSION:
        raise ImageCropError("Invalid raster dimensions")
    if width * height > MAX_AREA:
        raise ImageCropError("Raster dimensions exceed the pixel-area limit")
    return width, height


def probe_raster(source: Path, mime: str) -> tuple[int, int]:
    """Read bounded metadata for preview geometry without decoding image pixels."""
    if mime not in _markup.MIME_SIGNATURES:
        raise ImageCropError("Unsupported raster preview format")
    try:
        descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_size < 24 or
                    info.st_size > 6 * 1024 * 1024):
                raise ImageCropError("Image preview must be a bounded regular file")
            data = stream.read(256 * 1024)
    except OSError as error:
        raise ImageCropError("Cannot open image preview") from error
    if not any(data.startswith(signature)
               for signature in _markup.MIME_SIGNATURES[mime]):
        raise ImageCropError("Invalid image preview signature")
    if mime == "image/webp" and data[8:12] != b"WEBP":
        raise ImageCropError("Invalid WebP preview signature")
    return raster_dimensions(data, mime)


def compose_crop(data: bytes, mime: str, left: int, top: int,
                 width: int, height: int) -> bytes:
    """Create a standalone image viewport for one validated percentage rectangle."""
    if not (0 <= left <= 99 and 0 <= top <= 99 and
            1 <= width <= 100 and 1 <= height <= 100 and
            left + width <= 100 and top + height <= 100):
        raise ImageCropError("Crop percentages must describe a rectangle inside the image")
    image_w, image_h = raster_dimensions(data, mime)
    x1 = round(image_w * left / 100)
    y1 = round(image_h * top / 100)
    x2 = round(image_w * (left + width) / 100)
    y2 = round(image_h * (top + height) / 100)
    cropped_w, cropped_h = x2 - x1, y2 - y1
    if cropped_w < 1 or cropped_h < 1:
        raise ImageCropError("Crop must contain at least one actual pixel")
    ET.register_namespace("", SVG_NAMESPACE)
    root = ET.Element(f"{{{SVG_NAMESPACE}}}svg", {
        "viewBox": f"{x1} {y1} {cropped_w} {cropped_h}",
        "width": str(cropped_w), "height": str(cropped_h),
    })
    ET.SubElement(root, f"{{{SVG_NAMESPACE}}}image", {
        "x": "0", "y": "0", "width": str(image_w), "height": str(image_h),
        "preserveAspectRatio": "none",
        "href": f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}",
    })
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def crop_image(source: Path, mime: str, destination: Path, left: int,
               top: int, width: int, height: int) -> None:
    """Atomically create a private SVG crop while preserving source bytes."""
    if destination.suffix.lower() != ".svg" or destination.parent.is_symlink():
        raise ImageCropError("Crop destination must be a new SVG in a real directory")
    try:
        original = read_raster(source, mime)
    except ImageMarkupError as error:
        raise ImageCropError(str(error)) from error
    result = compose_crop(original, mime, left, top, width, height)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    try:
        fd = os.open(destination, flags, 0o600)
    except OSError as error:
        raise ImageCropError("Crop destination must not already exist") from error
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(result)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    """Build an SVG crop from native numeric percentage parameters."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--mime", required=True,
                        choices=("image/png", "image/jpeg", "image/gif", "image/webp"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--probe", action="store_true",
                        help="Print validated native width and height")
    for option in ("left", "top", "width", "height"):
        parser.add_argument(f"--{option}", type=int)
    args = parser.parse_args(argv)
    try:
        if args.probe:
            width, height = probe_raster(args.image, args.mime)
            print(width, height)
        elif args.output is None or any(
            getattr(args, name) is None for name in ("left", "top", "width", "height")
        ):
            raise ImageCropError("Select an output and complete crop rectangle")
        else:
            crop_image(args.image, args.mime, args.output, args.left, args.top,
                       args.width, args.height)
    except (ImageCropError, ImageMarkupError, OSError) as error:
        print(f"Image crop: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
