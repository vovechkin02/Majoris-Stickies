#!/usr/bin/env python3
"""Check release metadata and report the native qualification prerequisites.

This deliberately does not call a static check a successful native build.
Run after installing Debian 13 build dependencies, before Meson and dpkg.
"""

from __future__ import annotations

import argparse
import configparser
import re
import shutil
import stat
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NATIVE_EXECUTABLES = ("valac", "meson", "ninja", "pkg-config", "gcc")
NATIVE_PACKAGES = (
    "glib-2.0", "gio-2.0", "gee-0.8", "gtk4", "libadwaita-1", "sqlite3",
)


def check_metadata(root: Path) -> list[str]:
    """Find cross-file version, icon, installation and extension mismatches."""
    errors: list[str] = []
    meson = (root / "meson.build").read_text(encoding="utf-8")
    version_match = re.search(r"version:\s*'([^']+)'", meson)
    version = version_match.group(1) if version_match else None
    if not version:
        errors.append("Meson project version is missing")

    changelog = (root / "debian/changelog").read_text(encoding="utf-8")
    if version and not changelog.startswith(f"majoris-stickies ({version}-"):
        errors.append("Debian changelog is not using the Meson project version")

    desktop = configparser.ConfigParser(interpolation=None)
    desktop.read(root / "data/com.majoris.stickies.desktop", encoding="utf-8")
    if not desktop.has_section("Desktop Entry"):
        errors.append("Desktop entry is missing")
    else:
        if desktop["Desktop Entry"].get("Icon") != "com.majoris.stickies":
            errors.append("Desktop entry does not select the installed icon")
        if desktop["Desktop Entry"].get("Exec") != "majoris-stickies":
            errors.append("Desktop entry does not launch the native executable")

    metainfo = ET.parse(root / "data/com.majoris.stickies.metainfo.xml").getroot()
    releases = metainfo.find("releases")
    if releases is None or not releases.findall("release"):
        errors.append("AppStream release history is missing")
    elif version and releases.find("release").get("version") != version:
        errors.append("Newest AppStream release is not the Meson version")

    icon_path = root / "data/icons/com.majoris.stickies.svg"
    if not icon_path.exists():
        errors.append("Scalable application icon is missing")
    else:
        svg = ET.parse(icon_path).getroot()
        if svg.tag != "{http://www.w3.org/2000/svg}svg":
            errors.append("The application icon is not valid SVG")

    icon_install = "usr/share/icons/hicolor/scalable/apps/com.majoris.stickies.svg"
    if icon_install not in (root / "debian/majoris-stickies.install").read_text():
        errors.append("Debian package does not install the application icon")
    if "icons/com.majoris.stickies.svg" not in (
        root / "data/meson.build"
    ).read_text():
        errors.append("Meson install does not include the application icon")

    # Debian invokes debian/rules directly; ZIP extraction must preserve +x.
    if not (root / "debian/rules").stat().st_mode & stat.S_IXUSR:
        errors.append("Debian rules must be executable for dpkg-buildpackage")
    if not (root / "tools/stickies_auto_sync.py").stat().st_mode & stat.S_IXUSR:
        errors.append("The scheduled-sync worker must retain executable permissions")

    control = (root / "debian/control").read_text(encoding="utf-8")
    if not all(phrase in control for phrase in (
        "gnome-shell (>= 48)", "gnome-shell (<< 51)",
    )):
        errors.append("GNOME Shell dependency range is not constrained to 48–50")
    return errors


def missing_native_capabilities() -> list[str]:
    """Identify missing binary tools and pkg-config development interfaces."""
    missing = [name for name in NATIVE_EXECUTABLES if shutil.which(name) is None]
    if shutil.which("pkg-config") is None:
        missing.extend(f"pkg-config:{package}" for package in NATIVE_PACKAGES)
    else:
        for package in NATIVE_PACKAGES:
            result = subprocess.run(
                ["pkg-config", "--exists", package],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode != 0:
                missing.append(f"pkg-config:{package}")
    return missing


def main(argv: list[str] | None = None) -> int:
    """Print verifiable findings and fail requested native/release gates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-native", action="store_true")
    parser.add_argument("--release", action="store_true")
    arguments = parser.parse_args(argv)

    errors = check_metadata(ROOT)
    missing = missing_native_capabilities()
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if missing:
        print("Native prerequisites unavailable: " + ", ".join(missing))
    else:
        print("Native toolchain detected (compilation still must be run)")

    if arguments.release:
        control = (ROOT / "debian/control").read_text(encoding="utf-8")
        changelog = (ROOT / "debian/changelog").read_text(encoding="utf-8")
        if "packaging@example.invalid" in control + changelog:
            errors.append("Official packaging maintainer contact is not configured")
            print(f"ERROR: {errors[-1]}", file=sys.stderr)

    if errors or (missing and (arguments.require_native or arguments.release)):
        return 1
    print("Static release metadata is consistent; unrun native checks remain unqualified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
