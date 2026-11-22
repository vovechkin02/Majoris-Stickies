# Stage 9.3 — Store coordination and editor completion

**Status:** Source updated and offline regression checks run; native application
qualification is still outstanding. **SQLite schema v5 unchanged.**

## Implemented

1. **Coordinated store lifetime:** `src/native/store-session-lock.c` holds an
   exclusive nonblocking `flock` on the user-owned
   `<XDG_DATA_HOME>/majoris/stickies/.stickies-session.lock`. The C descriptor
   is owned by `StickiesApp`, acquired **before** opening SQLite and released
   after final database flush. Exchange import and sync use the identical
   file, and acquire the lock through a context manager until the operation
   exits. A live GUI startup and an in-progress sync/import cannot overlap
   under this protocol. Legacy callers not using this lock are not protected.
2. **Complete duplication invariant:** `duplicate_note()` is explicitly
   text-only and rejects attached notes; `duplicate_complete()` remains the
   attachment-preserving GUI action with ID remapping and rollback.
3. **Editor conveniences:** GTK4 header double-click collapse and explicit
   Ctrl+click HTTP(S) links within note text, validated by `SourceLink`.
4. **PDF pages:** `pdftoppm` remains the renderer, now accepting strict 320,
   640, 960 and 1280-pixel zoom levels. Images are displayed only by the
   Majoris Image view. Temporary previews have bounded size and are removed
   after use; the document schema is unchanged.

## Tests run in this source environment

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
node --experimental-default-type=module tests/integration/test_layout.mjs
gcc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -fsyntax-only \
    src/native/store-session-lock.c
```

The lock regression compiles a temporary native shared library and validates
real lock contention across the C and Python implementations. These tests
**do not** verify Vala compilation, GTK gestures, the optional ImageKit viewer,
GNOME Shell behavior, accessibility, or Debian binary packaging.

## Outstanding qualification and intentionally deferred features

- Build with `meson setup build -Dimagekit=disabled`, compile and run tests.
  Repeat with `-Dimagekit=enabled` on Majoris with matching ImageKit development
  packages. Test the new C/Vala lock interface, both gesture controls, and all
  PDF zoom steps under GTK4/Wayland.
- Test archive, Trash, attachment duplication and RTFD upgrade paths on real
  migrated notes. Qualify user timer startup/stop against live GUI activation.
- Verify keyboard/Orca, multi-monitor arrangements, shell extension GNOME
  48–50, and actual `.deb` installation/upgrade/removal and ISO integration.
- **Distribution blocker:** `packaging@example.invalid` is a placeholder.
  Replace only with the verified official Majoris packaging contact.
- Full macOS RTFD fidelity, semantic nested lists, spelling, image markup,
  PDF annotation, pressure-sensitive drawing, browser-source capture, and
  account-based cloud synchronization remain feature gaps. They have not been
  represented as implemented or qualified in this release.
