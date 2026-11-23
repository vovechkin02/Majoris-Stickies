#!/usr/bin/env python3
"""Inspect and compare bounded RTFD packages without modifying source documents.

TextEdit provenance is recorded only as an explicit macOS user attestation;
constructed fixtures are never presented as evidence of a TextEdit UI test.
Native visual appearance and application import/export remain separate checks.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import stat
import sys
from typing import Any

import stickies_rtfd as rtfd

MAX_EXPECTED_BYTES = 128 * 1024
MAX_RECORD_BYTES = 256 * 1024
MAX_DIFF_ITEMS = 16
RECORD_FORMAT = "majoris-textedit-evidence-1"
IMAGE_STYLE = re.compile(r"image_([0-9a-f-]{36})_([0-9]{2,4})\Z")


class QualificationError(ValueError):
    """Identify invalid fixture evidence or a failed semantic comparison."""


def _read_json(source: Path, limit: int) -> dict[str, Any]:
    """Read a bounded regular JSON file without traversing a final symlink."""
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(source, flags), "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= limit:
            raise QualificationError("Expected a bounded, ordinary JSON file")
        payload = stream.read(limit + 1)
        if len(payload) > limit:
            raise QualificationError("JSON file exceeds the qualification limit")
    try:
        record = json.loads(payload.decode("utf-8"))
    except (ValueError, UnicodeError) as error:
        raise QualificationError("Malformed UTF-8 qualification JSON") from error
    if not isinstance(record, dict):
        raise QualificationError("Qualification JSON must contain an object")
    return record


def _file_digest(source: Path, maximum: int) -> tuple[str, int]:
    """Hash a verified regular package member through its open descriptor."""
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(source, flags), "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= maximum:
            raise QualificationError("RTFD member exceeds a safe regular-file limit")
        digest = sha256()
        remaining = info.st_size
        while remaining:
            block = stream.read(min(remaining, 256 * 1024))
            if not block:
                raise QualificationError("RTFD member changed while hashing")
            digest.update(block)
            remaining -= len(block)
        if stream.read(1):
            raise QualificationError("RTFD member grew while hashing")
        return digest.hexdigest(), info.st_size


def _details(source: Path) -> dict[str, Any]:
    """Create stable text, style, inline-identity and attachment fingerprints."""
    text, formatting, assets = rtfd.inspect_package(source)
    native = rtfd.read_native_note(source, assets)
    if native is None:
        native = rtfd._external_note(source, assets)
    identities: dict[str, str] = {}
    if native is not None:
        text, formatting, identities = native

    asset_manifest: list[dict[str, Any]] = []
    hashes: dict[str, str] = {}
    for asset in sorted(assets, key=lambda item: item.name):
        fingerprint, size = _file_digest(asset, rtfd.MAX_ATTACHMENT_BYTES)
        hashes[asset.name] = fingerprint
        asset_manifest.append({
            "name": asset.name, "sha256": fingerprint, "bytes": size,
        })
    image_hashes = {identifier: hashes[name] for name, identifier in identities.items()}
    runs: list[tuple[int, int, str]] = []
    inline_positions: list[dict[str, Any]] = []
    for start, end, token in rtfd._rtf_export._spans(text, formatting):
        match = IMAGE_STYLE.fullmatch(token)
        if match:
            image_hash = image_hashes.get(match.group(1))
            if image_hash is None or text[start:end] != "\ufffc" or end != start + 1:
                raise QualificationError("Inline image cannot be matched to its package data")
            token = f"image_sha256_{image_hash}_{match.group(2)}"
            inline_positions.append({
                "position": start, "sha256": image_hash, "width": int(match.group(2)),
            })
        runs.append((start, end, token))
    runs.sort()
    inline_positions.sort(key=lambda item: (item["position"], item["sha256"]))
    styles = sorted({line[2] for line in runs})
    raw_rtf_digest, _ = _file_digest(source / "TXT.rtf", rtfd._rtf_import.MAX_INPUT_BYTES)
    package_manifest: list[dict[str, Any]] = []
    for member in sorted(source.iterdir(), key=lambda item: item.name):
        maximum = (
            rtfd._rtf_import.MAX_INPUT_BYTES if member.name == "TXT.rtf"
            else rtfd.MAX_MANIFEST_BYTES if member.name == "majoris.json"
            else rtfd.MAX_APPLE_METADATA_BYTES if member.name == ".DS_Store" or
            member.name.startswith("._") else rtfd.MAX_ATTACHMENT_BYTES
        )
        fingerprint, size = _file_digest(member, maximum)
        package_manifest.append({
            "name": member.name, "sha256": fingerprint, "bytes": size,
        })
    return {
        "package_manifest": package_manifest,
        "text": text,
        "formatting": formatting,
        "runs": runs,
        "asset_manifest": asset_manifest,
        "inline_positions": inline_positions,
        "styles": styles,
        "rtf_sha256": raw_rtf_digest,
        "semantic_style_sha256": sha256(_canonical(runs)).hexdigest(),
    }


def _canonical(value: Any) -> bytes:
    """Serialize bounded evidence deterministically with Unicode retained."""
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def inspect_fixture(source: Path) -> dict[str, object]:
    """Return a bounded, stable report from one validated RTFD package."""
    details = _details(source)
    text = details["text"]
    formatting = details["formatting"]
    return {
        "text_sha256": sha256(text.encode("utf-8")).hexdigest(),
        "formatting_sha256": sha256(formatting.encode("utf-8")).hexdigest(),
        "paragraph_styles": [
            token for token in details["styles"] if token.startswith("para-")
        ],
        "list_styles": [
            token for token in details["styles"] if token.startswith("list-")
        ],
        "attachments": [asset["name"] for asset in details["asset_manifest"]],
        "attachment_manifest": details["asset_manifest"],
        "package_manifest": details["package_manifest"],
        "inline_images": text.count("\ufffc"),
        "inline_positions": details["inline_positions"],
        "semantic_style_sha256": details["semantic_style_sha256"],
        "rtf_sha256": details["rtf_sha256"],
        "text": text,
    }


def check_fixture(source: Path, expected: dict[str, object]) -> dict[str, object]:
    """Fail on any explicitly asserted, source-grounded fixture property."""
    report = inspect_fixture(source)
    supported = set(report) | {"required_styles"}
    for name, value in expected.items():
        if name not in supported:
            raise QualificationError("Unsupported fixture expectation: " + name)
        if name == "required_styles":
            if not isinstance(value, list) or any(
                not isinstance(item, str) for item in value
            ):
                raise QualificationError("required_styles must be an array of tokens")
            found = report["paragraph_styles"] + report["list_styles"]
            if not all(item in found for item in value):
                raise QualificationError("TextEdit document lost required formatting")
        elif report[name] != value:
            raise QualificationError("TextEdit fixture mismatch: " + name)
    return report


def _style_delta(
    source: list[tuple[int, int, str]], target: list[tuple[int, int, str]],
) -> tuple[list[list[object]], list[list[object]]]:
    """Identify bounded canonical style differences ignoring span order."""
    old = Counter(tuple(run) for run in source)
    new = Counter(tuple(run) for run in target)
    lost = sorted((old - new).elements())
    gained = sorted((new - old).elements())
    return ([list(item) for item in lost[:MAX_DIFF_ITEMS]],
            [list(item) for item in gained[:MAX_DIFF_ITEMS]])


def _comparison(source: dict[str, Any], target: dict[str, Any]) -> dict[str, Any]:
    """Compare visible text, canonical formatting, image bindings, and data."""
    source_hashes = Counter(
        (item["sha256"], item["bytes"]) for item in source["asset_manifest"]
    )
    target_hashes = Counter(
        (item["sha256"], item["bytes"]) for item in target["asset_manifest"]
    )
    lost, gained = _style_delta(source["runs"], target["runs"])
    text_equal = source["text"] == target["text"]
    style_equal = source["runs"] == target["runs"]
    assets_equal = source_hashes == target_hashes
    positions_equal = source["inline_positions"] == target["inline_positions"]
    return {
        "equivalent": text_equal and style_equal and assets_equal and positions_equal,
        "text_preserved": text_equal,
        "styles_preserved": style_equal,
        "attachments_preserved": assets_equal,
        "inline_positions_preserved": positions_equal,
        "raw_rtf_bytes_equal": source["rtf_sha256"] == target["rtf_sha256"],
        "lost_styles": lost,
        "added_styles": gained,
        "lost_attachments": [
            {"sha256": digest, "bytes": size, "count": amount}
            for (digest, size), amount in sorted((source_hashes - target_hashes).items())
        ][:MAX_DIFF_ITEMS],
        "added_attachments": [
            {"sha256": digest, "bytes": size, "count": amount}
            for (digest, size), amount in sorted((target_hashes - source_hashes).items())
        ][:MAX_DIFF_ITEMS],
    }


def compare_fixtures(source: Path, target: Path) -> dict[str, Any]:
    """Compare portable semantics without requiring identical generated filenames."""
    return _comparison(_details(source), _details(target))


def _snapshot(report: dict[str, object]) -> str:
    """Bind a fixture report to its visible document and attachment bytes."""
    fields = (
        "text_sha256", "semantic_style_sha256", "rtf_sha256",
        "attachment_manifest", "inline_positions", "package_manifest",
    )
    return sha256(_canonical({key: report[key] for key in fields})).hexdigest()


def _textedit_version() -> str | None:
    """Read local macOS TextEdit bundle metadata, without launching the app."""
    info = Path("/System/Applications/TextEdit.app/Contents/Info.plist")
    if not info.is_file():
        return None
    try:
        with info.open("rb") as stream:
            value = plistlib.load(stream).get("CFBundleShortVersionString")
        return str(value) if value is not None else None
    except (OSError, ValueError, plistlib.InvalidFileException):
        return None


def record_fixture(
    source: Path, destination: Path, producer: str, attested: bool = False,
) -> dict[str, Any]:
    """Capture a non-overwriting checksum record with explicit provenance limits."""
    if producer not in {"textedit", "appkit", "majoris", "constructed"}:
        raise QualificationError("Unrecognized fixture producer")
    if producer == "textedit":
        if sys.platform != "darwin" or not attested:
            raise QualificationError(
                "TextEdit provenance requires macOS and explicit save confirmation"
            )
    elif attested:
        raise QualificationError("TextEdit confirmation applies only to TextEdit")
    report = inspect_fixture(source)
    record = {
        "format": RECORD_FORMAT,
        "producer": producer,
        "provenance": "user-attested" if producer == "textedit" else "declared",
        "fixture_name": source.name,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.system(),
        "macos_version": platform.mac_ver()[0] if sys.platform == "darwin" else None,
        "textedit_version": _textedit_version() if producer == "textedit" else None,
        "snapshot_sha256": _snapshot(report),
    }
    if destination.resolve().is_relative_to(source.resolve()):
        raise QualificationError("Evidence must not be written inside an RTFD source")
    if destination.parent.is_symlink() or not destination.parent.is_dir():
        raise QualificationError("Evidence destination requires a real parent directory")
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_CLOEXEC
    flags |= getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(destination, flags, 0o600), "wb") as stream:
        stream.write(_canonical(record) + b"\n")
    return record


def verify_record(source: Path, record_path: Path) -> dict[str, Any]:
    """Reject changed RTFD bytes or malformed qualification provenance."""
    record = _read_json(record_path, MAX_RECORD_BYTES)
    if record.get("format") != RECORD_FORMAT or record.get("producer") not in {
        "textedit", "appkit", "majoris", "constructed"
    }:
        raise QualificationError("Unsupported qualification evidence format")
    if record.get("fixture_name") != source.name:
        raise QualificationError("Qualification record refers to another fixture")
    if record.get("producer") == "textedit" and (
        record.get("platform") != "Darwin" or record.get("provenance") != "user-attested"
    ):
        raise QualificationError("TextEdit provenance is not a macOS user attestation")
    if record.get("snapshot_sha256") != _snapshot(inspect_fixture(source)):
        raise QualificationError("RTFD fixture differs from its recorded bytes")
    return record


def _legacy_inspect(argv: list[str]) -> int:
    """Retain the v0.9.12 positional fixture inspector and expected JSON mode."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="RTFD directory to inspect")
    parser.add_argument("--expected", type=Path, help="Optional expected properties JSON")
    arguments = parser.parse_args(argv)
    expected = (_read_json(arguments.expected, MAX_EXPECTED_BYTES)
                if arguments.expected is not None else {})
    print(json.dumps(check_fixture(arguments.source, expected),
                     sort_keys=True, ensure_ascii=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    """Dispatch deterministic read-only checks and explicit provenance capture."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments or arguments[0] not in {"inspect", "compare", "matrix", "record"}:
        try:
            return _legacy_inspect(arguments)
        except (OSError, ValueError, rtfd.RtfdError, rtfd.RtfImportError,
                rtfd.RtfExportError) as error:
            print("TextEdit fixture qualification failed: " + str(error), file=sys.stderr)
            return 1

    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Inspect a validated RTFD")
    inspect.add_argument("source", type=Path)
    inspect.add_argument("--expected", type=Path)
    compare = commands.add_parser("compare", help="Compare two RTFD semantics")
    compare.add_argument("source", type=Path)
    compare.add_argument("target", type=Path)
    compare.add_argument("--source-record", type=Path)
    compare.add_argument("--target-record", type=Path)
    matrix = commands.add_parser("matrix", help="Compare original, export and TextEdit resave")
    matrix.add_argument("original", type=Path)
    matrix.add_argument("majoris_export", type=Path)
    matrix.add_argument("textedit_resaved", type=Path)
    matrix.add_argument("--original-record", type=Path)
    matrix.add_argument("--export-record", type=Path)
    matrix.add_argument("--resaved-record", type=Path)
    record = commands.add_parser("record", help="Record bounded fixture byte evidence")
    record.add_argument("source", type=Path)
    record.add_argument("--output", type=Path, required=True)
    record.add_argument("--producer", required=True,
                        choices=["textedit", "appkit", "majoris", "constructed"])
    record.add_argument("--confirm-textedit-save", action="store_true")
    args = parser.parse_args(arguments)
    try:
        if args.command == "inspect":
            expected = _read_json(args.expected, MAX_EXPECTED_BYTES) if args.expected else {}
            result = check_fixture(args.source, expected)
        elif args.command == "record":
            result = record_fixture(args.source, args.output, args.producer,
                                    args.confirm_textedit_save)
        elif args.command == "compare":
            if args.source_record:
                verify_record(args.source, args.source_record)
            if args.target_record:
                verify_record(args.target, args.target_record)
            result = compare_fixtures(args.source, args.target)
            result["visual_review_required"] = True
        else:
            evidence: list[str] = []
            for source, record_path in (
                (args.original, args.original_record),
                (args.majoris_export, args.export_record),
                (args.textedit_resaved, args.resaved_record),
            ):
                if record_path is not None:
                    evidence.append(verify_record(source, record_path)["producer"])
                else:
                    evidence.append("unrecorded")
            original = _details(args.original)
            exported = _details(args.majoris_export)
            resaved = _details(args.textedit_resaved)
            source_export = _comparison(original, exported)
            export_resaved = _comparison(exported, resaved)
            source_resaved = _comparison(original, resaved)
            result = {
                "equivalent": source_export["equivalent"] and
                    export_resaved["equivalent"] and source_resaved["equivalent"],
                "original_to_export": source_export,
                "export_to_textedit": export_resaved,
                "original_to_textedit": source_resaved,
                "producers": evidence,
                "authentic_textedit_recorded": evidence[0] == "textedit" and
                    evidence[2] == "textedit",
                "native_app_import_and_visual_review_required": True,
            }
        print(json.dumps(result, sort_keys=True, ensure_ascii=True))
        if args.command in {"compare", "matrix"} and not result["equivalent"]:
            return 1
    except (OSError, ValueError, rtfd.RtfdError, rtfd.RtfImportError,
            rtfd.RtfExportError) as error:
        print("TextEdit fixture qualification failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
