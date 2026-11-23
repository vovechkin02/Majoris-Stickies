# Majoris Stickies 0.9.7 — Media markup, source capture and qualification

**Status:** Source implementation and offline regression tests complete; native
Vala/GTK, Majoris Image, GNOME Wayland and Debian binary builds **not run** here.
SQLite schema **v7**, existing managed attachments, and portable note formats
are unchanged.

## Implemented changes

1. **Source ZIP permissions:** `debian/rules` and
   `tools/stickies_auto_sync.py` are executable again. The ZIP builder records
   the UNIX mode bits so a normal POSIX extraction preserves those permissions.
   The release preflight checks the new media helper's installed path and mode.
2. **Direct inline-image resizing:** a small drag handle adjusts existing
   inline image width. Widths snap to the existing 16-pixel grid, bounded at
   96–960 pixels. The original GTK scale remains available for keyboard and
   assistive-technology interaction. The same serialized `image_UUID_width`
   token is used; no migration is needed.
3. **Explicit clipboard source capture:** the Note Options menu includes
   **Use Clipboard URL as Source**. Only an intentional user action reads the
   clipboard. Existing `SourceLink.normalize` validation still requires an
   HTTP(S) URL, prevents embedded credentials and limits the field to 2048
   bytes. No website is inferred from other application windows, and nothing
   monitors the clipboard in the background.
4. **Non-destructive raster markup:** ImageKit displays the selected PNG,
   JPEG, GIF or WebP, and the existing GTK `InkCanvas` provides a transparent
   pen layer. Saving produces a **new SVG attachment**, preserving the
   original raster. The helper embeds up to 1 MiB of verified raster bytes in
   an inert SVG `data:` reference and accepts only bounded native numeric pen
   strokes. It never decodes images. Its inputs reject symbolic links, active
   SVG/XML, scripts, URLs, markup injection, excessive stroke counts, oversized
   payloads and existing output destinations.
5. **PDF page visual markup:** the ImageKit/Poppler PDF page navigator provides
   **Mark Up Page**. Poppler rasterizes the selected page, the same pen overlay
   annotates its *preview*, and the result is attached as a separate SVG. This
   does **not** write annotations into the PDF file or modify its structure.
   The 1 MiB raster limit also applies; complex/highly detailed PDF preview
   pages may be too large and will fail safely.

## Architecture and compatibility

- `InlineImageFormat` owns snap/validation semantics. `InlineImageController`
  only translates GTK drag gestures to slider updates; the existing change
  signal persists the new image-width token. No second image-layout state.
- `ImageMarkupEditor` owns transient GTK pen/preview widgets and requires
  Majoris Image at build time. Dynamic overlay drawing is an intentional
  imperative-widget exception to XML layout, consistent with the existing
  `InkCanvas`; no replacement image decoder has been added.
- `ImageMarkupTransfer` owns the spawned helper, cancellation and temporary
  file lifetime. It calls the existing `NoteRepository.attach_file` API and
  does not write SQLite or other managed files itself. `NoteWindow` remains
  responsible only for user actions, success/failure feedback and PDF-preview
  lifetime handoff.
- `stickies_image_markup.py` validates the image and bounded SVG numeric input,
  then writes an `O_EXCL`, owner-only new SVG file. The helper is not a general
  SVG parser/editor or media codec. It uses Python standard-library modules
  and executes no external commands, shell, or network requests.
- GObject/GTK signals provide the required Observer-like interaction; no new
  GoF hierarchy is warranted. Every image window owns its editor, and native
  asynchronous tasks are canceled with the note window's existing cancellable.
- All new source and documentation uses American English and follows the
  organization-wide engineering standards v1.8.

## Offline checks

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
python3 tools/release_preflight.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
```

The new integration tests exercise real SVG construction, the image bytes and
original file remaining unchanged, script/foreign element rejection, output
clobber avoidance, MIME/signature/size/symlink checks and CLI stdin transport.
The new native unit test checks direct drag width snapping but cannot run
without `valac` and the GTK/Gee development packages.

## Required native release gates (not executed here)

On Debian 13 with the compatible Majoris Image SDK:

```sh
meson setup build-minimal -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build-minimal
meson test -C build-minimal --print-errorlogs
meson setup build-full -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-full
meson test -C build-full --print-errorlogs
xvfb-run -a dbus-run-session -- python3 tools/smoke_gui.py build-full/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

Verify ImageKit loading, source clipboard validation, pointer drag sizing,
non-destructive raster markup and PDF page markup on GNOME Wayland, including
window close/cancellation, malformed media, multiple monitors, light/dark
styles, accessible controls, and PDF preview cleanup. Test installing the new
helper in the Debian package and the Majoris ISO. The official Debian
packaging maintainer must replace the existing placeholder address before
release. Do not claim passing build or runtime checks without running them.

## Still missing or partial

Full macOS RTFD/NSFileWrapper fidelity, fully semantic nested paragraph/list
structures, destructive or lossless raster crop editing, actual PDF annotation
objects, pressure/tilt pen data, automatic originating-browser discovery,
account-based cloud synchronization, unrestricted simultaneous desktop note
windows, and database-level search pagination remain outside this update.
The markup SVG is a separate export, not a replacement for the original
attachment. Preview-to-pen coordinate alignment and SVG reopening still need
native runtime qualification. This source ZIP is **not release-qualified**.
