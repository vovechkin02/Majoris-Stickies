# Stage 6 — Implementation and qualification

## Scope delivered

Stage 6 v0.6.0 introduces notes Archive/Trash/Restore and pinning, schema v5,
attachment-inclusive async duplication, expanded selected-text formatting,
list-prefix editing, find/replace, file drag-and-drop, startup preferences,
Show/Hide All Note Windows and compatibility updates to backups/exchange.

## Data migration and reversibility

- v4 → v5: `ALTER TABLE notes ADD COLUMN status ... DEFAULT 0`, `pinned ... DEFAULT 0`.
- Note UUIDs, body, formatting, timestamps, assets, and reminder fields are
  preserved; new columns are written by the ordinary parameterized note UPSERT.
- Archive/Trash update lifecycle flags and do not unlink attachments.
- Permanent deletion remains explicit and is invoked through the Trash flow.
- Old v4 note bundles use the original manifest field set. New lifecycle
  flags are included when they carry non-default information.

## Verification run in this environment

The environment is Debian 13 but lacks valac, Meson, GTK4/libadwaita SDK and
GNOME Shell. Neither the application nor the extension can be compiled or
executed here. This is **not a build-qualified release**.

Available tests:

```sh
python3 tests/integration/test_resource_layout.py data
python3 -m unittest discover -s tests/integration -p 'test_stage5_exchange.py'
python3 -m unittest discover -s tests/integration -p 'test_stage6_exchange.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
```

## Required native qualification on Debian 13 / Majoris GNOME

```sh
sudo apt-get install meson ninja-build valac gcc pkgconf python3 nodejs \
  libglib2.0-dev libgee-0.8-dev libgtk-4-dev libadwaita-1-dev libsqlite3-dev
meson setup build -Dimagekit=disabled -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/install-root"
```

Then build with `-Dimagekit=enabled` on a system with a version-compatible
Majoris Image development package; verify preview parity for image assets.
Test with the shipping GNOME Shell release and Wayland compositor, including
multi-display topology changes and shell extension enable/disable transitions.

## Interactive smoke tests

- Migrate an existing v4 database, then verify note IDs, Unicode text and
  existing attachments remain intact after reopen.
- Create active, archived, trashed and pinned notes; verify manager filters,
  restoration, hiding/showing windows, and permanent-delete confirmations.
- Duplicate a note with several managed images and PDFs; verify the duplicate
  has new attachment UUIDs, preserved MIME, independent files, and rollback on
  failed copies. Simulate source disappearing mid-copy.
- Validate search and replace with Unicode, selection boundaries and
  replacement text containing the search term.
- Validate colors, size, alignment and font tags after save/reopen/copy as HTML;
  compare output with GTK rendering on light and dark themes.
- Check Drag & Drop with 1, 16 and 17 files, MIME mismatch, file growth during
  copy, a missing source and cancellation; verify no duplicate metadata rows.
- Save a default note color, create a new note and verify that the preset is
  used without altering existing notes. Test a malformed or symlink preferences
  file; no implicit trust is allowed.
- Opt into autostart and disable it again. Verify a foreign or symlink desktop
  entry is never overwritten or removed.
- Test accessibility with Orca, tab focus and note windows while the manager is
  closed. Measure large notes and rich-text serialization on target hardware.

## Deferred features

Do not claim full macOS/Windows parity until RTF/RTFD, inline embedded
images/PDFs, enhanced source tracking, unrestricted styling, true top-level
transparency and all-workspace behavior have dedicated implementation and tests.
