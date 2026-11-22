# Stage 9.2 qualification and remaining feature scope

**Version:** 0.9.2  
**Status:** Source updated; Python regression checks run; native build unverified.  
**SQLite schema:** v5, unchanged. Existing note IDs and attachment formats retained.

## Implemented and verified in the source

1. Dynamic text formatting in HTML export and clipboard generation: font,
   point size, RGB, alignment, and list annotations. Unicode text is escaped.
   Explicit inline-image spans can become bounded raster data URIs only when
   their managed file is regular, small, and has a matching image signature.
   Plain text and unsupported images use visible non-path placeholders.
2. XDG data-directory defaults shared with the GTK application across backup,
   exchange, and background reminder Python tools. Relative XDG directories
   fall back to the standard home directory; explicit CLI paths remain.
3. A two-command reminder snooze action that updates the existing reminder
   deadline and resets its delivery marker via the repository API.
4. Filter-before-sort search with original pinned/recent comparison semantics.
5. Optional auto-sync worker with user-private configuration and a disabled
   systemd timer. Only the existing explicit `--app-closed` local merge is
   invoked, and the worker requires a working D-Bus user session. Deletion
   propagation is not invoked automatically.

## Regression and release checks

Run from the repository root:

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
python3 tools/release_preflight.py
node tests/integration/test_layout.mjs
```

After installing Debian 13 dependencies and the compatible GTK4/libadwaita
and Majoris Image development packages, the native release gates are:

```sh
meson setup build -Dimagekit=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-image -Dimagekit=enabled
meson compile -C build-image
meson test -C build-image --print-errorlogs
```

Perform a live GTK clipboard test with mixed right-to-left and emoji text,
custom fonts and colors, and supported inline PNG/JPEG/GIF/WebP files. Paste
into a second editor to verify HTML/data-URI compatibility. Verify clipboard
size limits and fallback for SVG/PDF, symlinks, corrupt files, or more than
eight images. Test snooze and background reminders on a real user D-Bus
session. Confirm a scheduled sync waits until the GUI is closed, and does
not propagate permanent deletions. Verify the disabled timer remains disabled
on package installation. Run GNOME Shell/Mutter (48–50) multi-monitor and
accessibility checks, then build and install/uninstall Debian packages.

## Explicitly outstanding

- Native Vala compilation, Xvfb/GTK smoke testing, Majoris Image-enabled build,
  Wayland/Shell runtime, and Debian binary/ISO integration are not verified.
- Debian maintainer metadata remains a placeholder and must be replaced by an
  authorized official contact before distribution.
- macOS RTFD full fidelity, nested semantic lists, complete spell checking,
  image crop/markup, PDF annotations, automatic originating-browser source
  capture, pen pressure/tilt, and account-based cloud sync remain incomplete.
- The local sync timer does not automatically merge while Stickies is running.
  The D-Bus verification and exchange command provide best-effort separation,
  not a transaction with the GTK application's SQLite connection. It is an
  optional convenience, not a substitute for backups or explicit conflict review.
- `NoteRepository` still keeps active note objects in memory; full-text-indexed
  database search and incremental card reuse remain future performance work.

Do not designate this source package a fully qualified release candidate until
actual native compilation and target-desktop testing complete.
