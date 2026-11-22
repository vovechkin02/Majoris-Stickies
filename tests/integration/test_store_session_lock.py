"""Verify the shared C/Python store lock prevents cross-process edits."""

from __future__ import annotations

import ctypes
import importlib.util
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "stickies_exchange_session", ROOT / "tools/stickies_exchange.py"
)
assert SPEC and SPEC.loader
exchange = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exchange)


class StoreSessionLockTests(unittest.TestCase):
    """Exercise real advisory file locks, symlink rejection, and lifetime."""

    def setUp(self) -> None:
        """Use one disposable, user-owned data directory for every case."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.store = self.root / "stickies"
        self.store.mkdir(mode=0o700)

    def test_two_exchange_sessions_cannot_overlap(self) -> None:
        """A second importer cannot enter the same store concurrently."""
        with exchange.exclusive_store_lock(self.store):
            with self.assertRaisesRegex(exchange.ExchangeError, "open or another"):
                with exchange.exclusive_store_lock(self.store):
                    self.fail("Exclusive notes-store locking was bypassed")
        with exchange.exclusive_store_lock(self.store):
            self.assertTrue((self.store / ".stickies-session.lock").is_file())

    def test_reject_symlink_and_insecure_lock_file(self) -> None:
        """Reject existing paths that an attacker could use to redirect locking."""
        target = self.root / "other"
        target.mkdir()
        linked = self.root / "linked"
        linked.symlink_to(self.store, target_is_directory=True)
        with self.assertRaises(exchange.ExchangeError):
            with exchange.exclusive_store_lock(linked):
                self.fail("Symlinked store was accepted")
        lock = self.store / ".stickies-session.lock"
        lock.symlink_to(target)
        with self.assertRaises(exchange.ExchangeError):
            with exchange.exclusive_store_lock(self.store):
                self.fail("Symlinked lock was accepted")
        lock.unlink()
        lock.touch(mode=0o666)
        lock.chmod(0o644)
        with self.assertRaises(exchange.ExchangeError):
            with exchange.exclusive_store_lock(self.store):
                self.fail("World-readable lock was accepted")

    @unittest.skipUnless(shutil.which("gcc"), "GCC unavailable for native lock exercise")
    def test_native_and_exchange_lock_interoperate(self) -> None:
        """A live C lock excludes the Python importer and vice versa."""
        library = self.root / "libstore-session-lock.so"
        subprocess.run(
            ["gcc", "-std=c11", "-D_GNU_SOURCE", "-Wall", "-Wextra", "-Werror",
             "-fPIC", "-shared", str(ROOT / "src/native/store-session-lock.c"),
             "-o", str(library)],
            check=True, capture_output=True, text=True,
        )
        native = ctypes.CDLL(str(library))
        native.stickies_store_lock_acquire.argtypes = [ctypes.c_char_p]
        native.stickies_store_lock_acquire.restype = ctypes.c_int
        native.stickies_store_lock_release.argtypes = [ctypes.c_int]
        native.stickies_store_lock_release.restype = None
        directory = os.fsencode(self.store)
        descriptor = native.stickies_store_lock_acquire(directory)
        self.assertGreaterEqual(descriptor, 0)
        try:
            with self.assertRaises(exchange.ExchangeError):
                with exchange.exclusive_store_lock(self.store):
                    self.fail("Python exchange bypassed the native lock")
        finally:
            native.stickies_store_lock_release(descriptor)
        with exchange.exclusive_store_lock(self.store):
            self.assertEqual(native.stickies_store_lock_acquire(directory), -1)
        descriptor = native.stickies_store_lock_acquire(directory)
        self.assertGreaterEqual(descriptor, 0)
        native.stickies_store_lock_release(descriptor)


if __name__ == "__main__":
    unittest.main()
