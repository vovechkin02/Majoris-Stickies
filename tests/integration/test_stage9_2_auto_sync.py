"""Exercise opt-in folder synchronization without touching a real user store."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "stickies_auto_sync", ROOT / "tools/stickies_auto_sync.py"
)
assert SPEC and SPEC.loader
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


class AutoSyncTests(unittest.TestCase):
    """Require explicit configuration, an inactive app, and no deletion flags."""

    def setUp(self) -> None:
        """Keep the config, data and exchange folder under a disposable root."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.folder = self.root / "shared"
        self.folder.mkdir()
        self.store = self.root / "data" / "majoris" / "stickies"
        self.store.mkdir(parents=True)
        context = patch.dict(os.environ, {
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/not/a/real/bus",
        })
        context.start()
        self.addCleanup(context.stop)

    def test_configure_requires_private_regular_file(self) -> None:
        """Write 0600 config and reject a symlink or world-readable replacement."""
        path = sync.configure(self.folder)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(sync.configured_folder(), self.folder)
        with self.assertRaises(sync.AutoSyncError):
            sync.configure(self.folder)
        path.chmod(0o644)
        with self.assertRaises(sync.AutoSyncError):
            sync.configured_folder()
        path.unlink()
        path.symlink_to(self.folder)
        with self.assertRaises(sync.AutoSyncError):
            sync.configured_folder()

    def test_reject_relative_and_control_character_share_paths(self) -> None:
        """Never persist relative folders or control-character configuration values."""
        with self.assertRaises(sync.AutoSyncError):
            sync.configure(Path("relative"))
        suspicious = self.root / "bad\nname"
        suspicious.mkdir()
        with self.assertRaises(sync.AutoSyncError):
            sync.configure(suspicious)

    def test_run_skips_active_session_and_prohibits_deletions(self) -> None:
        """Use the existing exchange CLI only after confirming Stickies is closed."""
        sync.configure(self.folder)
        with patch.object(sync, "application_is_running", return_value=True):
            with patch.object(sync.subprocess, "run") as run:
                self.assertIn("Skipped", sync.synchronize_once())
                run.assert_not_called()
        response = subprocess.CompletedProcess([], 0, "Synchronized: unchanged=1", "")
        with patch.object(sync, "application_is_running", return_value=False):
            with patch.object(sync.subprocess, "run", return_value=response) as run:
                self.assertIn("unchanged=1", sync.synchronize_once())
                args = run.call_args.args[0]
                self.assertEqual(args[0], "majoris-stickies-exchange")
                self.assertEqual(args[1:3], ["--data-dir", str(self.store)])
                self.assertIn("--app-closed", args)
                self.assertNotIn("--propagate-deletions", args)

    def test_missing_session_bus_fails_closed(self) -> None:
        """Do not run a background merge if session ownership is unverifiable."""
        sync.configure(self.folder)
        with patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": ""}):
            with self.assertRaises(sync.AutoSyncError):
                sync.synchronize_once()
        self.assertEqual(sync.main(["once", "--dry-run"]), 1)


if __name__ == "__main__":
    unittest.main()
