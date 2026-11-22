# Stage 2 qualification record

## Status and evidence

Source version: **0.2.0**. The included code is a Stage 2 implementation
candidate, not a runtime-qualified release.

| Verification gate | Result in packaging container |
| --- | --- |
| XML files well formed | PASS — parsed with Python ElementTree |
| UI resource / GtkChild static tests | PASS — 5 Python tests |
| Shell JavaScript parse | PASS — `node --check` |
| Shell metadata JSON | PASS — parsed with Python |
| Meson configuration / C and Vala compilation | NOT RUN — toolchain unavailable |
| Vala unit tests | NOT RUN — toolchain unavailable |
| GTK window interactions | NOT RUN — GTK runtime unavailable |
| Majoris Image GTK4 API / preview | NOT RUN — library unavailable |
| GNOME Shell integration (Wayland) | NOT RUN — compositor unavailable |

Static checks only verify source structure and syntax for the parsed file
types. They cannot verify generated Vala/C code, GTK template types,
libadwaita APIs, D-Bus integration or correct GUI behavior.

## Required Debian 13 checks

```sh
sudo apt-get install -y --no-install-recommends \
  build-essential meson ninja-build valac python3 \
  libglib2.0-dev libgee-0.8-dev libgtk-4-dev \
  libadwaita-1-dev libsqlite3-dev
meson setup build -Dimagekit=disabled -Dshell_extension=false
meson compile -C build
meson test -C build --print-errorlogs
./build/src/majoris-stickies
```

If the target ships `majoris-image-gtk4-1`, configure an additional build with
`meson setup build-image -Dimagekit=enabled`, then compile and test preview
loading with installed image fixtures. Validate error handling for corrupted
images through ImageKit rather than duplicating decoding logic.

For desktop window behavior, install and enable the `shell/` extension only
on a test account and validate using a GNOME Shell session matching the
Majoris image. Test always-on-top, unset always-on-top, grid/cascade, each
sort order, note position restoration after restart, multiple monitors and
Shell extension disable/reload. Without the extension, verify that the
floating action returns an informative failure and leaves preferences intact.

## Behavioral acceptance checks

1. Upgrade a real copy of a Stage 1 database and compare all old fields and
   IDs; confirm data persists across multiple restarts.
2. Type, select and style Unicode text. Close and reopen the note, checking
   formatting boundaries after inserts and deletions.
3. Import malformed UTF-8 and files above 2 MiB; confirm neither erases an
   existing note. Export text and inspect the result. Plain text deliberately
   loses style formatting.
4. Attach a small image and PDF, close and reopen the note, open them via file
   cards, remove one, and verify the managed copy is gone.
5. Test a file that grows during asynchronous copying and disk permission
   failures; failed operations must not leave attachment metadata behind.
6. Collapse/expand a note, toggle translucent paper, close/reopen editor,
   and verify saved dimensions and flags.
7. Force a SQLite write error during editing: note close must fail safely
   and preserve the still-visible editor contents.
8. Confirm manager search, card display, duplicate, deletion and shortcuts
   still work after schema migration.
9. Validate GNOME Shell placement/stacking, including extension absence,
   screen work-area changes, shutdown and crash recovery.

## Known scope limits

This release does not implement full macOS Stickies rich-text parity: RTF and
RTFD interchange, exact font selection and sizing, advanced lists, inline PDF
pages, document markup, or true toplevel window transparency are deferred.
Compositor-dependent behavior has no verified runtime guarantee until tested
on Majoris GNOME Shell. Continue to Stage 3 only after the build and Stage 2
regression gates are met.
