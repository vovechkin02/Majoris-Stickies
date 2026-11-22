# Stage 8 final functional pass — v0.8.2

## Scope and compatibility

The update is based on the supplied v0.8.1 Stage 8 completion repository.
The SQLite `user_version` remains **5** and no existing migration or stored
field has been renamed. Image attachments remain UUID-addressed private
`.asset` files. Backups, note sharing, and the local folder exchange protocol
remain compatible with previous versions.

## Implemented

1. **Import race protection** — Plain-text imports now capture editor revision,
   content and formatting before asynchronous reads, checking all three again
   immediately before replacing the text. The same preservation principle
   already applied to RTF/RTFD imports.
2. **RTFD metadata preservation** — The Python package validator reads the
   optional `majoris.json`, enforces exact file matching, bounded UTF-8 display
   names, extension-to-MIME consistency, and no symlinks or unsupported files.
   The native import service consumes its validated, escaped output and supplies
   the restored original names/types to repository-controlled attachment copies.
   Missing metadata falls back to the generated attachment names.
3. **Positioned inline images** — The GTK editor uses `GtkTextChildAnchor` at
   insertion positions. `InlineImageController` creates and restores these
   widgets; `InlineImageFormat` validates references, which contain only an
   attachment UUID and one of three sizes (160/240/320 px). `get_slice()` is
   used when persisting the buffer so U+FFFC anchor positions are not lost.
   Majoris ImageKit performs actual image display when compiled in.
4. **Duplication correctness** — The cloned attachment ID mapping is applied
   to inline-style references only after the complete managed-copy operation
   succeeds; failures still roll back the duplicate note.
5. **Expanded formatting** — GTK font and color dialogs produce validated
   `face_`, `point_` and `rgb_` style tags. Paragraph list kinds are persisted
   alongside portable visible markers, with Return-to-continue handling.

## Bounds and security

- Attachment copies are capped at 50 MiB per file; the RTFD package validator
  additionally caps the entire bundle at 128 MiB and 32 attachments.
- Import and export never execute embedded RTF objects or scripts.
- Relative paths, symlinks, file-name traversal, malformed metadata, and
  unsupported MIME mappings are rejected before any RTFD asset is imported.
- Inline styles are validated by attachment identity and predefined size.
  They never contain an absolute file path or an image byte payload.
- Font-family names are UTF-8 validated and length-bounded; font size is
  restricted to 8–72 points; color is six hexadecimal RGB digits.

## Known limitations

- **Native build is not yet verified**: `valac`, Meson, and GTK4/libadwaita
  development libraries are unavailable in this environment. Compile the
  project on Debian 13 before enabling it in the ISO.
- Rendered inline images currently support three width presets rather than
  arbitrary drag handles. Rich clipboard and Apple RTFD round-trip of image
  anchors are not lossless.
- RTFD support is a validated Majoris-compatible directory subset, not full
  macOS `NSFileWrapper`/RTFD interoperability.
- Paragraph kinds still include visible prefixes so older clients preserve
  the text. Nested semantic list trees and cross-paragraph renumbering remain
  incomplete.
- Image crop and annotation editing, full PDF editing, spell checking, and
  automatic source URL detection are not implemented in this pass.
- GNOME Shell compositor features still require runtime integration testing.
- The Debian maintainer email is a placeholder awaiting official project
  packaging metadata.

## Verification checklist for Stage 9

1. Run `meson setup build -Dimagekit=enabled` and `meson compile -C build` on
   Debian 13 with the correct Majoris Image development headers; repeat with
   `-Dimagekit=disabled`.
2. Run `meson test -C build --print-errorlogs` (including Vala unit tests).
3. Launch two note windows with GNOME Wayland; insert, resize, close/reopen,
   duplicate, remove, and restore managed image attachments. Verify no stale
   parent widgets or disappearing object markers.
4. Import text/RTF/RTFD while editing; verify the revision guards prevent
   overwrites. Check Unicode attachment names and legacy no-manifest packages.
5. Run Orca, clipboard, migration, backup/recovery and Debian binary package
   tests, then verify installation/removal in the Majoris ISO build.
