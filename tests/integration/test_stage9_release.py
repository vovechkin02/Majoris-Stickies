"""Check observable Stage 9 release contracts and safe temporary cleanup."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_preview_module():
    """Import the installed helper implementation without relying on sys.path."""
    spec = importlib.util.spec_from_file_location(
        "stickies_pdf_preview", ROOT / "tools/stickies_pdf_preview.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseQualificationTests(unittest.TestCase):
    """Test release contracts that do not require an installed GTK runtime."""

    def test_metadata_preflight_passes_without_native_toolchain(self) -> None:
        """Treat unavailable native dependencies as unqualified, not failed metadata."""
        result = subprocess.run(
            [sys.executable, "tools/release_preflight.py"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Static release metadata is consistent", result.stdout)

    def test_release_gate_requires_official_packaging_contact(self) -> None:
        """Never label a source ZIP distribution-ready with dummy contact data."""
        result = subprocess.run(
            [sys.executable, "tools/release_preflight.py", "--release"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        control = (ROOT / "debian/control").read_text(encoding="utf-8")
        if "packaging@example.invalid" in control:
            self.assertEqual(result.returncode, 1)
            self.assertIn("Official packaging maintainer contact", result.stderr)
        else:
            self.assertNotIn("Official packaging maintainer contact", result.stderr)

    def test_cleanup_reclaims_only_old_owned_single_page_directories(self) -> None:
        """Preserve fresh previews, symlinks and unrelated user directories."""
        preview = load_preview_module()
        now = time.time()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old = root / "majoris-stickies-pdf-old"
            old.mkdir(mode=0o700)
            page = old / "page.png"
            page.write_bytes(b"\x89PNG\r\n\x1a\n")
            old_time = now - preview.STALE_PREVIEW_SECONDS - 100
            os.utime(page, (old_time, old_time))
            os.utime(old, (old_time, old_time))

            new = root / "majoris-stickies-pdf-new"
            new.mkdir(mode=0o700)
            (new / "page.png").write_bytes(b"PNG")

            unrelated = root / "majoris-stickies-pdf-userfiles"
            unrelated.mkdir(mode=0o700)
            (unrelated / "important.txt").write_text("keep", encoding="utf-8")
            os.utime(unrelated, (old_time, old_time))
            link = root / "majoris-stickies-pdf-link"
            link.symlink_to(unrelated, target_is_directory=True)

            self.assertEqual(preview.cleanup_stale_previews(root, now=now), 1)
            self.assertFalse(old.exists())
            self.assertTrue(new.is_dir())
            self.assertEqual((unrelated / "important.txt").read_text(), "keep")
            self.assertTrue(link.is_symlink())

    def test_cleanup_never_removes_world_readable_directory(self) -> None:
        """Leave unfamiliar, nonprivate directories alone regardless of age."""
        preview = load_preview_module()
        now = time.time()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            directory = root / "majoris-stickies-pdf-public"
            directory.mkdir(mode=0o755)
            page = directory / "page.png"
            page.write_bytes(b"PNG")
            old_time = now - preview.STALE_PREVIEW_SECONDS - 200
            os.utime(page, (old_time, old_time))
            os.utime(directory, (old_time, old_time))
            self.assertEqual(preview.cleanup_stale_previews(root, now=now), 0)
            self.assertTrue(page.is_file())


if __name__ == "__main__":
    unittest.main()
