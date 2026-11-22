# Stage 8 completion pass — v0.8.1

## Scope and preservation

Applied to the provided v0.8.0 source. SQLite schema remains v5. Existing
notes, formatting tokens, attachment IDs, backup and `.stickies` share formats
are not migrated or renamed. Majoris Image continues to own all image
previews; Poppler is invoked only for PDF-page rasterization.

## Implemented work

- RTF importer parses bounded `fonttbl` and `colortbl` entries, derives
  declared font families, and maps colors only when sufficiently similar to
  the application's supported colors. Unrecognized values remain unstyled.
  The importer keeps its finite nesting, span, text, file and control limits.
- Asynchronous RTF/RTFD operations capture the editor revision and visible
  text/style state before conversion. A concurrent edit cancels replacement,
  avoiding lost user edits; a RTFD import rolls back newly added files on
  failure. It imports only local regular files.
- New RTFD-style directory exchange contains `TXT.rtf`, metadata, and
  numbered neighboring image/PDF files. Exports refuse existing destinations;
  imports reject symlinks/unknown entries and keep bounded sizes/counts.
  Limitations: this is a supported **Majoris RTFD subset**, not complete Apple
  NSFileWrapper or NeXTGraphic inline placement compatibility. The RTFD
  source-to-GTK path imports rich text plus separate attachments.
- `PdfPreviewService` supports bounded pages 1–250. The GTK attachment panel
  offers Previous/Next only after the user expands a PDF; Poppler performs
  rasterization and ImageKit displays each PNG. Helpers delete private temp
  previews after successful or failed load, instead of accumulating pages.
- The Show All Notes desktop launcher action now actually opens note windows
  (up to the 64-window registration limit). The GNOME Shell extension offers
  verified-window compositor-wide opacity with an explicit paper-only
  fallback. On disabling the extension it restores actor opacity.
- Editor gestures can toggle a checklist by clicking its leading glyph, and
  menu commands indent/outdent paragraphs. Lists are still represented as
  portable text and **not semantic or nested structured nodes**.

## Verification in the authoring environment

Run the exact available checks:

```sh
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 -m unittest discover -s tests/integration -p 'test_stage*.py'
python3 tests/integration/test_resource_layout.py data
python3 tools/check_source_docs.py
python3 -m compileall -q tools tests
node --check shell/majoris-stickies@majoris.org/extension.js
node --check shell/majoris-stickies@majoris.org/layout.js
node tests/integration/test_layout.mjs
```

**Not run locally:** `valac`, Meson compilation, Vala unit-test binaries,
GTK accessibility, GNOME Wayland runtime, installed ImageKit, and Debian binary
packaging. Their missing prerequisites remain a Stage 9 release blocker, not
passing tests. Re-run the Debian 13 CI native gates before shipping.

## Native qualification cases (Stage 9)

1. Compile with `-Dimagekit=disabled` and `-Dimagekit=enabled`; run all
   Meson tests and an Xvfb startup/activation smoke test.
2. Test RTF import while typing, RTFD export/import with multiple attachments,
   failed copy rollback, cancelling dialogs, and malicious symlink rejection.
3. Preview a multi-page PDF, navigate beyond the final page, remove an
   attachment while rendering, and confirm temporary files are cleaned up.
4. On actual GNOME Wayland, enable/disable the Shell extension, register and
   unregister notes, toggle opacity and floating, restart the application,
   rearrange monitors, and test all-workspace visibility.
5. Verify pointer checkbox hit testing, keyboard-only editing, Orca names,
   large note sets, migration/backup compatibility, and Debian installation.
6. Replace `packaging@example.invalid` with a real, approved packaging address
   before distribution. Do not invent a maintainer address.

## Still missing against full macOS/Windows feature parity

- Correctly positioned inline image widgets with persistent anchor-to-file
  mapping and editable resizing; arbitrary image markup/cropping.
- Fully conforming native macOS RTFD file wrappers and NeXTGraphic positions.
- Semantic nested text lists, unrestricted font and color palettes, spellcheck.
- Rich PDF document editing/navigation beyond the bounded previewer.
- Automatic browser source detection and optional cloud/background services.

These must not be reported as complete or qualified by passing static tests.
